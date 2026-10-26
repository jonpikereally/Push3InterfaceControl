import SwiftUI

enum Theme {
    static let panel = Color(red: 0.13, green: 0.13, blue: 0.14)
    static let card = Color(white: 0.2)
    static let cardHover = Color(white: 0.24)
    static let stroke = Color.white.opacity(0.08)
    static let blue = Color(red: 0.25, green: 0.47, blue: 1.0)
    static let red = Color(red: 0.91, green: 0.27, blue: 0.22)
    static let amber = Color(red: 0.96, green: 0.6, blue: 0.18)
    static let green = Color(red: 0.24, green: 0.72, blue: 0.36)
}

/// Settings, saved in UserDefaults (com.jonpike.pushbar).
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    /// Strips whose left and right move together. All of them by default.
    @Published var unlinked: Set<String> { didSet { d.set(Array(unlinked), forKey: "unlinked") } }

    private init() {
        unlinked = Set(d.stringArray(forKey: "unlinked") ?? [])
    }

    func linked(_ strip: Strip) -> Bool { !unlinked.contains(strip.rawValue) }

    func toggleLink(_ strip: Strip) {
        if unlinked.contains(strip.rawValue) { unlinked.remove(strip.rawValue) } else { unlinked.insert(strip.rawValue) }
    }
}

/// What the popover's "…" button and the status item's right-click show.
struct MenuActions {
    var showMenu: (NSView?) -> Void = { _ in }
}

struct ContentView: View {
    @ObservedObject var push = Push.shared
    @ObservedObject var reporter = ProblemBanner.shared
    var actions: MenuActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !push.connected {
                BannerView(error: AppError(.notConnected))
            } else if let e = reporter.error {
                BannerView(error: e, dismiss: { reporter.error = nil })
            }
            if push.connected {
                StripRow(strip: .master, title: "Master", icon: "speaker.wave.2.fill",
                         help: "Push's overall output level. The Mac's volume keys move this when Push is the sound output.")
                Divider().overlay(Theme.stroke)
                StripRow(strip: .main, title: "Main Out", icon: "hifispeaker.2.fill", help: "Outputs 1/2 on the back of Push")
                StripRow(strip: .phones, title: "Headphones", icon: "headphones", help: "The headphone jack")
                Divider().overlay(Theme.stroke)
                StripRow(strip: .inputs, title: "Inputs", icon: "mic.fill", sideNames: ["In 1", "In 2"],
                         help: "Input gain for Inputs 1 and 2 (0 to +20 dB)")
                Divider().overlay(Theme.stroke)
                footer
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("PushBar").font(.system(size: 14, weight: .bold))
            Text(push.connected ? "Push 3 · \(Self.rate(push.sampleRate))" : "Push 3 not connected")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            MenuAnchor(show: actions.showMenu)
                .frame(width: 16, height: 16)
                .help("Updates, Open at Login, Quit")
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                PillToggle(title: "Mac Output", on: push.isMacOutput, tint: Theme.blue) { push.makeDefault(output: true) }
                    .help(push.isMacOutput ? "Push is the Mac's sound output. Pick another in System Settings → Sound to switch away."
                                           : "Play the Mac's sound through Push")
                PillToggle(title: "Mac Input", on: push.isMacInput, tint: Theme.blue) { push.makeDefault(output: false) }
                    .help(push.isMacInput ? "Push is the Mac's sound input. Pick another in System Settings → Sound to switch away."
                                          : "Use Push's inputs as the Mac's microphone")
            }
            HStack {
                Text("Sample Rate").font(.system(size: 12, weight: .medium))
                Spacer()
                Menu(Self.rate(push.sampleRate)) {
                    ForEach(push.sampleRates, id: \.self) { r in
                        Button { push.setSampleRate(r) } label: {
                            if r == push.sampleRate { Label(Self.rate(r), systemImage: "checkmark") } else { Text(Self.rate(r)) }
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.system(size: 12))
            }
        }
    }

    static func rate(_ hz: Double) -> String {
        hz == 0 ? "—" : hz.truncatingRemainder(dividingBy: 1000) == 0
            ? "\(Int(hz / 1000)) kHz" : String(format: "%.1f kHz", hz / 1000)
    }
}

/// The most recent problem, shown at the top of the popover until dismissed.
final class ProblemBanner: ObservableObject {
    static let shared = ProblemBanner()
    @Published var error: AppError?
}

/// One control group: a title row with mute and link, then one fader when
/// linked or one per side when not.
struct StripRow: View {
    let strip: Strip
    let title: String
    let icon: String
    var sideNames = ["L", "R"]
    let help: String
    @ObservedObject var push = Push.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let chs = push.channels(strip)
        let stereo = chs.count > 1
        let linked = !stereo || prefs.linked(strip)
        let muted = !chs.isEmpty && chs.allSatisfy(\.mute)
        let canMute = chs.contains(where: \.hasMute)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 14)
                Text(title).font(.system(size: 13, weight: .semibold)).help(help)
                if stereo {
                    Button { prefs.toggleLink(strip) } label: {
                        Image(systemName: "link")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(linked ? Theme.blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(linked ? "Left and right move together. Click to adjust them separately."
                                 : "Left and right move separately. Click to link them.")
                }
                Spacer()
                if linked, let first = chs.first {
                    Text(muted ? "Muted" : Self.format(first.db, gain: strip == .inputs))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(muted ? Theme.red : .secondary)
                }
                if canMute {
                    Button { push.setMute(strip, !muted) } label: {
                        Image(systemName: muted ? (strip == .inputs ? "mic.slash.fill" : "speaker.slash.fill")
                                                : (strip == .inputs ? "mic.fill" : "speaker.fill"))
                            .font(.system(size: 10))
                            .foregroundStyle(muted ? Theme.red : .secondary)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                    .help(muted ? "Unmute" : "Mute")
                }
            }
            if linked, let first = chs.first {
                LevelSlider(value: first.scalar, dimmed: muted) { push.setVolume(strip, scalar: $0) }
                    .frame(height: 18)
            } else {
                ForEach(Array(chs.enumerated()), id: \.offset) { i, ch in
                    HStack(spacing: 6) {
                        Text(i < sideNames.count ? sideNames[i] : "\(i + 1)")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                        LevelSlider(value: ch.scalar, dimmed: ch.mute) { push.setVolume(strip, side: i, scalar: $0) }
                            .frame(height: 18)
                        Text(ch.mute ? "Muted" : Self.format(ch.db, gain: strip == .inputs))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(ch.mute ? Theme.red : .secondary)
                            .frame(width: 58, alignment: .trailing)
                        if ch.hasMute {
                            Button { push.setMute(strip, side: i, !ch.mute) } label: {
                                Image(systemName: strip == .inputs ? (ch.mute ? "mic.slash.fill" : "mic.fill")
                                                                   : (ch.mute ? "speaker.slash.fill" : "speaker.fill"))
                                    .font(.system(size: 9))
                                    .foregroundStyle(ch.mute ? Theme.red : .secondary)
                                    .frame(width: 14)
                            }
                            .buttonStyle(.plain)
                            .help(ch.mute ? "Unmute \(sideNames[min(i, sideNames.count - 1)])" : "Mute \(sideNames[min(i, sideNames.count - 1)])")
                        }
                    }
                }
            }
        }
    }

    static func format(_ db: Double, gain: Bool) -> String {
        if !gain && db <= -89.5 { return "−∞" }
        let s = String(format: "%.1f dB", abs(db) < 0.05 ? 0 : db)
        return (db > 0.05 ? "+" : "") + s.replacingOccurrences(of: "-", with: "−")
    }
}

/// A thin fader over CoreAudio's 0…1 scalar.
struct LevelSlider: View {
    let value: Double
    let dimmed: Bool
    let onChange: (Double) -> Void
    @State private var dragging: Double?
    @State private var lastSent = Date.distantPast

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let pos = dragging ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 4)
                Capsule().fill(dimmed ? Color.gray : Theme.blue).frame(width: max(4, pos * w), height: 4)
                Circle().fill(Color(white: 0.75)).frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: pos * (w - 14))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let f = min(max(v.location.x / w, 0), 1)
                    dragging = f
                    if Date().timeIntervalSince(lastSent) > 0.033 {
                        lastSent = Date()
                        onChange(f)
                    }
                }
                .onEnded { _ in
                    if let f = dragging { onChange(f) }
                    dragging = nil
                })
        }
    }
}

struct PillToggle: View {
    let title: String
    let on: Bool
    let tint: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Circle().fill(on ? tint : Color.white.opacity(0.18)).frame(width: 7, height: 7)
                    .shadow(color: on ? tint : .clear, radius: 3)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? tint.opacity(0.22) : (hover ? Theme.cardHover : Theme.card)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct BannerView: View {
    let error: AppError
    var dismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                Text(error.code.summary).font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let d = error.detail, !d.isEmpty {
                Text(d).font(.system(size: 10).monospaced()).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(error.code.hint).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Error code: \(error.code.rawValue)").font(.system(size: 10, weight: .medium).monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if let dismiss { Button("Dismiss", action: dismiss).controlSize(.small) }
                Button("Copy Details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ErrorReporter.details(error), forType: .string)
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.amber.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.amber.opacity(0.35)))
        .help(ErrorReporter.tooltip)
    }
}

/// An "…" button that pops the app menu from itself.
struct MenuAnchor: NSViewRepresentable {
    let show: (NSView?) -> Void

    func makeNSView(context: Context) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More")!,
                         target: context.coordinator, action: #selector(Coordinator.click(_:)))
        b.isBordered = false
        b.contentTintColor = .secondaryLabelColor
        return b
    }

    func updateNSView(_ nsView: NSButton, context: Context) { context.coordinator.show = show }
    func makeCoordinator() -> Coordinator { Coordinator(show: show) }

    final class Coordinator: NSObject {
        var show: (NSView?) -> Void
        init(show: @escaping (NSView?) -> Void) { self.show = show }
        @objc func click(_ sender: NSButton) { show(sender) }
    }
}
