import AppKit

/// Every failure a user can run into has a stable code, so it can be looked up
/// on the public error list (ERRORS.md) or pasted into an LLM. Add new codes
/// here and to ERRORS.md together, and never show a user an error without one.
/// Codes are never reused or renumbered.
enum ErrorCode: String, CaseIterable {
    // 1xx — updates
    case noUpdateSource = "PB-101"
    case badUpdateSource = "PB-102"
    case updateSourceUnreachable = "PB-103"
    case updateServerError = "PB-104"
    case updateInfoMalformed = "PB-105"
    case updateDownloadFailed = "PB-106"
    case updateUnpackFailed = "PB-107"
    case updateMissingApp = "PB-108"
    case updateWrongApp = "PB-109"
    case updateDamagedApp = "PB-110"
    case updateInstallerFailed = "PB-111"
    case updateSwapFailed = "PB-112"
    // 2xx — Push 3's audio interface
    case notConnected = "PB-201"
    case setFailed = "PB-202"
    case sampleRateFailed = "PB-203"
    case defaultDeviceFailed = "PB-204"
    // 4xx — login item
    case loginItemFailed = "PB-401"
    // 6xx — reserved for install.sh and the Install PushBar.command script (release.sh)
    // 9xx — anything not covered above
    case unexpected = "PB-999"

    var summary: String {
        switch self {
        case .noUpdateSource: return "No update source is set."
        case .badUpdateSource: return "The update source isn't a web link or a file path."
        case .updateSourceUnreachable: return "Couldn't reach the update source."
        case .updateServerError: return "The update server returned an error."
        case .updateInfoMalformed: return "The update information is damaged or in the wrong format."
        case .updateDownloadFailed: return "Couldn't download the update."
        case .updateUnpackFailed: return "Couldn't unpack the downloaded update."
        case .updateMissingApp: return "The downloaded update doesn't contain PushBar."
        case .updateWrongApp: return "The downloaded update is a different app."
        case .updateDamagedApp: return "The downloaded update is damaged."
        case .updateInstallerFailed: return "Couldn't start installing the update."
        case .updateSwapFailed: return "Installing the update failed, so the previous version was kept."
        case .notConnected: return "Push 3's audio interface isn't connected."
        case .setFailed: return "Push 3 didn't accept a volume or mute change."
        case .sampleRateFailed: return "Couldn't change Push 3's sample rate."
        case .defaultDeviceFailed: return "Couldn't make Push 3 the Mac's sound output or input."
        case .loginItemFailed: return "Couldn't change Open at Login."
        case .unexpected: return "Something unexpected went wrong."
        }
    }

    var hint: String {
        switch self {
        case .noUpdateSource, .badUpdateSource:
            return "Set one with “Update Source…” in the menu, or leave it empty to use the built-in source."
        case .updateSourceUnreachable:
            return "Check your internet connection and try again."
        case .updateServerError, .updateDownloadFailed:
            return "Try again in a few minutes. If it keeps happening, download the latest version from GitHub."
        case .updateInfoMalformed, .updateUnpackFailed, .updateMissingApp, .updateWrongApp, .updateDamagedApp:
            return "The published update is broken. Download the latest version from GitHub instead."
        case .updateInstallerFailed, .updateSwapFailed:
            return "Make sure PushBar is in ~/Applications and that the folder isn't locked, then try again."
        case .notConnected:
            return "Make sure Push is plugged in over USB-C and switched on. If you just quit Live, Push may have gone to sleep: unplug its USB cable and plug it back in."
        case .setFailed:
            return "Unplug Push and plug it back in, then try again. If Live is open, it may be holding the setting."
        case .sampleRateFailed:
            return "Another app (Live, a DAW) may be locking the rate. Quit it, or change the rate in Audio MIDI Setup."
        case .defaultDeviceFailed:
            return "Choose Push yourself in System Settings → Sound."
        case .loginItemFailed:
            return "You can add PushBar yourself in System Settings → General → Login Items."
        case .unexpected:
            return "Try again. If it keeps happening, copy the details and ask for help."
        }
    }
}

struct AppError: LocalizedError {
    let code: ErrorCode
    /// Technical specifics (paths, system error text). Never user content.
    let detail: String?

    init(_ code: ErrorCode, _ detail: String? = nil) {
        self.code = code
        self.detail = detail
    }

    init(wrapping error: Error, as code: ErrorCode = .unexpected) {
        if let e = error as? AppError { self = e } else { self.init(code, error.localizedDescription) }
    }

    var errorDescription: String? { "\(code.summary) (\(code.rawValue))" }
}

/// Logs every error to ~/Library/Application Support/PushBar/errors.log and
/// shows it to the user with its code: in an alert, or as a menu bar row for
/// background failures.
final class ErrorReporter {
    enum Surface {
        case alert     // shown right away
        case menu      // "⚠️ Problem PB-xxx" row in the menu bar dropdown
        case logOnly   // e.g. an automatic update check while offline
    }

    static let shared = ErrorReporter()
    /// The public error list. Both URLs work without a GitHub account; the raw
    /// one is plain text, which AI assistants read most reliably.
    static let helpURL = "https://github.com/jonpikereally/Push3InterfaceControl/blob/main/ERRORS.md"
    static let plainTextHelpURL = "https://raw.githubusercontent.com/jonpikereally/Push3InterfaceControl/main/ERRORS.md"

    /// Hover text for anything that shows an error.
    static let tooltip = "Look up this error code on the PushBar error list: \(helpURL)\n"
        + "You can also give that page and the copied error details to an AI assistant for help."

    /// Latest background problem waiting in the menu, if any.
    private(set) var pending: AppError?
    var onChange: () -> Void = {}
    private var lastLogged: [ErrorCode: Date] = [:]

    static let logURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PushBar", isDirectory: true)
            .appendingPathComponent("errors.log")
    }()

    func report(_ error: AppError, surface: Surface, title: String = "PushBar ran into a problem") {
        DispatchQueue.main.async {
            self.log(error)
            switch surface {
            case .alert:
                self.present(error, title: title)
            case .menu:
                self.pending = error
                self.onChange()
            case .logOnly:
                break
            }
        }
    }

    func clearPending() {
        pending = nil
        onChange()
    }

    /// Shows the error with its code. `actions` become extra buttons; returns
    /// the index of the action picked, or nil for OK.
    @discardableResult
    func present(_ error: AppError, title: String, actions: [String] = []) -> Int? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        var text = error.code.summary
        if let d = error.detail, !d.isEmpty { text += "\n\n\(d)" }
        text += "\n\n\(error.code.hint)\n\nError code: \(error.code.rawValue)"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        for a in actions { alert.addButton(withTitle: a) }
        alert.addButton(withTitle: "Copy Error Details")
        alert.addButton(withTitle: "Open Error List")
        Self.addTooltips(to: alert)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if response == actions.count + 1 {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(Self.details(error), forType: .string)
            return nil
        }
        if response == actions.count + 2 {
            if let url = URL(string: Self.helpURL) { NSWorkspace.shared.open(url) }
            return nil
        }
        if response >= 1 && response <= actions.count { return response - 1 }
        return nil
    }

    /// Puts the error-list hover text on every piece of text in the alert,
    /// and on the alert itself for the space between them.
    static func addTooltips(to alert: NSAlert) {
        alert.layout()
        func walk(_ view: NSView) {
            if view is NSTextField { view.toolTip = tooltip }
            view.subviews.forEach(walk)
        }
        if let content = alert.window.contentView {
            content.toolTip = tooltip
            walk(content)
        }
    }

    /// Copyable report: everything needed to troubleshoot, nothing private.
    static func details(_ error: AppError) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "Apple Silicon"
        #else
        let arch = "Intel"
        #endif
        var lines = ["PushBar error \(error.code.rawValue): \(error.code.summary)"]
        if let d = error.detail, !d.isEmpty { lines.append("Details: \(d)") }
        lines.append("Suggested fix: \(error.code.hint)")
        lines.append("PushBar v\(AppVersion.version) (built \(AppVersion.built)), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), \(arch)")
        lines.append("Time: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Error code list: \(helpURL)")
        lines.append("Plain-text error list for AI assistants: \(plainTextHelpURL)")
        return lines.joined(separator: "\n")
    }

    private func log(_ error: AppError) {
        // The same code repeating (e.g. a full disk failing every save) is
        // logged at most once a minute.
        let now = Date()
        if let last = lastLogged[error.code], now.timeIntervalSince(last) < 60 { return }
        lastLogged[error.code] = now

        let line = "\(ISO8601DateFormatter().string(from: now)) \(error.code.rawValue) v\(AppVersion.version) "
            + error.code.summary + (error.detail.map { " — \($0)" } ?? "") + "\n"
        let url = Self.logURL
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 512 * 1024 {
            let old = url.deletingPathExtension().appendingPathExtension("old.log")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
