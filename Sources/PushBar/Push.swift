import Combine
import CoreAudio
import Foundation

/// A group of Push 3 controls that the popover shows as one row.
enum Strip: String, CaseIterable {
    case master, main, phones, inputs

    var scope: AudioObjectPropertyScope {
        self == .inputs ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
    }

    /// The element names Push reports for each side. Master is element 0, the
    /// device-wide volume macOS's own volume keys move.
    var elementNames: [String] {
        switch self {
        case .master: return []
        case .main: return ["Analog Out L", "Analog Out R"]
        case .phones: return ["Headphones L", "Headphones R"]
        case .inputs: return ["Analog In L", "Analog In R"]
        }
    }

    /// Element numbers seen on Push 3 (Oct 2026), used if the names change.
    var fallbackElements: [UInt32] {
        switch self {
        case .master: return [0]
        case .main: return [1, 2]
        case .phones: return [3, 4]
        case .inputs: return [1, 2]
        }
    }
}

/// Live mirror of Push 3's audio interface controls, read and written through
/// CoreAudio, so it works whether or not Live is running.
final class Push: ObservableObject {
    static let shared = Push()

    struct Channel: Equatable {
        /// 0…1, CoreAudio's own fader curve (the same one macOS's volume uses).
        var scalar: Double = 0
        var db: Double = 0
        var mute = false
        var hasMute = false
    }

    @Published var device: AudioObjectID?
    @Published var channels: [Strip: [Channel]] = [:]
    @Published var dbRange: [Strip: ClosedRange<Double>] = [:]
    @Published var sampleRate: Double = 0
    @Published var sampleRates: [Double] = []
    @Published var isMacOutput = false
    @Published var isMacInput = false

    var connected: Bool { device != nil }

    private var elements: [Strip: [UInt32]] = [:]
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDefaultInputDevice] {
            var a = CA.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refreshDevice() }
            AudioObjectAddPropertyListenerBlock(system, &a, DispatchQueue.main, block)
        }
        refreshDevice()
    }

    // MARK: - Reading

    private func refreshDevice() {
        let found = Self.findPush()
        if found != device {
            detach()
            device = found
            if let found { attach(found) }
        }
        refreshAll()
    }

    static func findPush() -> AudioObjectID? {
        CA.objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).first { id in
            let uid = CA.string(id, kAudioDevicePropertyDeviceUID) ?? ""
            let name = CA.string(id, kAudioObjectPropertyName) ?? ""
            return uid.hasPrefix("AppleUSBAudioEngine:Ableton:Ableton Push 3") || name == "Ableton Push 3 Audio"
        }
    }

    private func attach(_ id: AudioObjectID) {
        elements = [:]
        for strip in Strip.allCases {
            elements[strip] = resolve(strip, on: id)
            var range = CA.address(kAudioDevicePropertyVolumeRangeDecibels, strip.scope, elements[strip]?.first ?? 0)
            var r = AudioValueRange()
            var size = UInt32(MemoryLayout<AudioValueRange>.size)
            if AudioObjectGetPropertyData(id, &range, 0, nil, &size, &r) == noErr {
                dbRange[strip] = r.mMinimum...r.mMaximum
            }
        }
        // Push's own volume knob, Live, or Audio MIDI Setup can change these too.
        for strip in Strip.allCases {
            for e in elements[strip] ?? [] {
                for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                    listen(id, CA.address(selector, strip.scope, e))
                }
            }
        }
        listen(id, CA.address(kAudioDevicePropertyNominalSampleRate))
    }

    private func listen(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) {
        var a = address
        guard AudioObjectHasProperty(id, &a) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refreshAll() }
        if AudioObjectAddPropertyListenerBlock(id, &a, DispatchQueue.main, block) == noErr {
            deviceListeners.append((a, block))
        }
    }

    private func detach() {
        if let device {
            for (address, block) in deviceListeners {
                var a = address
                AudioObjectRemovePropertyListenerBlock(device, &a, DispatchQueue.main, block)
            }
        }
        deviceListeners = []
        elements = [:]
    }

    /// Finds each side's element by name, falling back to the known numbers.
    private func resolve(_ strip: Strip, on id: AudioObjectID) -> [UInt32] {
        guard !strip.elementNames.isEmpty else { return strip.fallbackElements }
        var byName: [String: UInt32] = [:]
        for e in UInt32(0)...32 {
            if let n = CA.string(id, kAudioObjectPropertyElementName, strip.scope, e), !n.isEmpty, byName[n] == nil {
                byName[n] = e
            }
        }
        let found = strip.elementNames.compactMap { byName[$0] }
        return found.count == strip.elementNames.count ? found : strip.fallbackElements
    }

    func refreshAll() {
        guard let id = device else {
            channels = [:]
            sampleRate = 0
            isMacOutput = false
            isMacInput = false
            return
        }
        var next: [Strip: [Channel]] = [:]
        for strip in Strip.allCases {
            next[strip] = (elements[strip] ?? []).map { e in
                var c = Channel()
                c.scalar = Double(CA.float(id, kAudioDevicePropertyVolumeScalar, strip.scope, e) ?? 0)
                c.db = Double(CA.float(id, kAudioDevicePropertyVolumeDecibels, strip.scope, e) ?? 0)
                if let m = CA.uint(id, kAudioDevicePropertyMute, strip.scope, e) {
                    c.hasMute = true
                    c.mute = m != 0
                }
                return c
            }
        }
        if next != channels { channels = next }
        sampleRate = CA.double(id, kAudioDevicePropertyNominalSampleRate) ?? 0
        sampleRates = CA.sampleRates(id)
        let system = AudioObjectID(kAudioObjectSystemObject)
        isMacOutput = CA.uint(system, kAudioHardwarePropertyDefaultOutputDevice) == id
        isMacInput = CA.uint(system, kAudioHardwarePropertyDefaultInputDevice) == id
    }

    func channels(_ strip: Strip) -> [Channel] { channels[strip] ?? [] }

    // MARK: - Writing

    /// Sets one side (0 = left, 1 = right), or every side when `side` is nil.
    func setVolume(_ strip: Strip, side: Int? = nil, scalar: Double) {
        let v = Float32(min(max(scalar, 0), 1))
        write(strip, side: side, kAudioDevicePropertyVolumeScalar, what: "volume") { id, a in
            var value = v
            return AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    func setMute(_ strip: Strip, side: Int? = nil, _ on: Bool) {
        write(strip, side: side, kAudioDevicePropertyMute, what: "mute") { id, a in
            var value: UInt32 = on ? 1 : 0
            return AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }

    private func write(_ strip: Strip, side: Int?, _ selector: AudioObjectPropertySelector, what: String,
                       _ set: (AudioObjectID, inout AudioObjectPropertyAddress) -> OSStatus) {
        guard let id = device else { ErrorReporter.shared.report(AppError(.notConnected), surface: .menu); return }
        let all = elements[strip] ?? []
        let targets = side.map { $0 < all.count ? [all[$0]] : [] } ?? all
        for e in targets {
            var a = CA.address(selector, strip.scope, e)
            let status = set(id, &a)
            if status != noErr {
                ErrorReporter.shared.report(AppError(.setFailed, "\(strip.rawValue) \(what), element \(e): \(CA.describe(status))"),
                                            surface: .menu)
            }
        }
        refreshAll()
    }

    func setSampleRate(_ rate: Double) {
        guard let id = device else { return }
        var a = CA.address(kAudioDevicePropertyNominalSampleRate)
        var value = rate
        let status = AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
        if status != noErr {
            ErrorReporter.shared.report(AppError(.sampleRateFailed, "\(Int(rate)) Hz: \(CA.describe(status))"), surface: .menu)
        }
        refreshAll()
    }

    /// Makes Push the Mac's sound output (and alert sounds), or its sound input.
    func makeDefault(output: Bool) {
        guard var id = device else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        let selectors = output
            ? [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice]
            : [kAudioHardwarePropertyDefaultInputDevice]
        for selector in selectors {
            var a = CA.address(selector)
            let status = AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)
            if status != noErr {
                ErrorReporter.shared.report(AppError(.defaultDeviceFailed, "\(output ? "output" : "input"): \(CA.describe(status))"),
                                            surface: .menu)
                break
            }
        }
        refreshAll()
    }
}

/// Small typed wrappers around the CoreAudio property calls.
enum CA {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ element: UInt32 = 0) -> String? {
        var a = address(selector, scope, element)
        guard AudioObjectHasProperty(id, &a) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func objects(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func float(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                      _ scope: AudioObjectPropertyScope, _ element: UInt32) -> Float32? {
        var a = address(selector, scope, element)
        guard AudioObjectHasProperty(id, &a) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func uint(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ element: UInt32 = 0) -> UInt32? {
        var a = address(selector, scope, element)
        guard AudioObjectHasProperty(id, &a) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func double(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Double? {
        var a = address(selector)
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func sampleRates(_ id: AudioObjectID) -> [Double] {
        var a = address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: .init(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ranges) == noErr else { return [] }
        return ranges.map(\.mMinimum)
    }

    /// OSStatus as its four-character code when it is one, e.g. 'who?'.
    static func describe(_ status: OSStatus) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((UInt32(bitPattern: status) >> $0) & 0xff) }
        if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }), let s = String(bytes: bytes, encoding: .ascii) {
            return "OSStatus '\(s)' (\(status))"
        }
        return "OSStatus \(status)"
    }
}
