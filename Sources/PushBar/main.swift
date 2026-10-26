import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let menu = NSMenu()
    private var updateMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var problemMenuItem: NSMenuItem!
    private var bag = Set<AnyCancellable>()

    private let push = Push.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let host = NSHostingController(rootView: ContentView(actions: MenuActions(
            showMenu: { [weak self] view in self?.popMenu(from: view) })))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)

        buildMenu()
        ErrorReporter.shared.onChange = { [weak self] in
            ProblemBanner.shared.error = ErrorReporter.shared.pending
            self?.refreshProblemItem()
        }
        Updater.shared.onChange = { [weak self] in self?.refreshUpdateItem() }
        Updater.shared.startAutomaticChecks()
        reportFailedUpdateIfAny()

        push.$device.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshIcon() } }.store(in: &bag)
        // Dismissing the popover's banner also clears the menu's problem row.
        ProblemBanner.shared.$error.sink { e in
            if e == nil, ErrorReporter.shared.pending != nil { DispatchQueue.main.async { ErrorReporter.shared.clearPending() } }
        }.store(in: &bag)
        push.start()
        refreshIcon()
    }

    // MARK: - Status item

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popMenu(from: nil)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            push.refreshAll()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func popMenu(from view: NSView?) {
        menuNeedsUpdate(menu)
        if let view {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
        } else if let button = statusItem.button {
            popover.performClose(nil)
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        }
    }

    private func refreshIcon() {
        let name = Updater.shared.available != nil ? "arrow.up.circle.fill" : "square.grid.3x3.fill"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "PushBar")
        statusItem.button?.appearsDisabled = !push.connected
        statusItem.button?.toolTip = push.connected ? "PushBar" : "PushBar — Push 3 isn't connected (PB-201)"
    }

    // MARK: - Menu

    private func buildMenu() {
        problemMenuItem = NSMenuItem(title: "", action: #selector(showPendingProblem), keyEquivalent: "")
        problemMenuItem.target = self
        problemMenuItem.isHidden = true
        menu.addItem(problemMenuItem)

        let midi = NSMenuItem(title: "Open Audio MIDI Setup", action: #selector(openAudioMIDISetup), keyEquivalent: "")
        midi.target = self
        menu.addItem(midi)

        loginMenuItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())

        updateMenuItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateMenuItem.target = self
        menu.addItem(updateMenuItem)

        let source = NSMenuItem(title: "Update Source…", action: #selector(editUpdateSource), keyEquivalent: "")
        source.target = self
        menu.addItem(source)

        let github = NSMenuItem(title: "PushBar on GitHub", action: #selector(openGitHub), keyEquivalent: "")
        github.target = self
        menu.addItem(github)

        let version = NSMenuItem(title: "Version \(AppVersion.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit PushBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        menu.autoenablesItems = false
        for item in menu.items where item.action != nil { item.isEnabled = true }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        refreshProblemItem()
    }

    @objc private func openAudioMIDISetup() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            ErrorReporter.shared.report(AppError(.loginItemFailed, error.localizedDescription),
                                        surface: .alert, title: "Couldn't change Open at Login")
        }
        loginMenuItem.state = service.status == .enabled ? .on : .off
    }

    // MARK: - Updates

    private func refreshUpdateItem() {
        if let m = Updater.shared.available {
            updateMenuItem.title = "⬆︎ Install Update to v\(m.version)…"
        } else {
            updateMenuItem.title = "Check for Updates…"
        }
        refreshIcon()
    }

    @objc private func checkForUpdates() {
        if let m = Updater.shared.available {
            offerInstall(m)
            return
        }
        updateMenuItem.title = "Checking for Updates…"
        Updater.shared.check { [weak self] result in
            guard let self else { return }
            self.refreshUpdateItem()
            switch result {
            case .success(let m?):
                self.offerInstall(m)
            case .success(nil):
                let alert = NSAlert()
                alert.messageText = "PushBar is up to date"
                alert.informativeText = "You're running v\(AppVersion.version), the newest version available."
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            case .failure(let error):
                self.showUpdateError(error)
            }
        }
    }

    private func offerInstall(_ m: UpdateManifest) {
        let alert = NSAlert()
        alert.messageText = "Update to PushBar v\(m.version)?"
        var info = "You have v\(AppVersion.version)."
        if let notes = m.notes, !notes.isEmpty { info += "\n\nWhat's new:\n\(notes)" }
        info += "\n\nPushBar will quit, update itself and reopen. Your settings are kept, "
            + "and there are no permissions to grant again."
        alert.informativeText = info
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        updateMenuItem.title = "Installing Update…"
        updateMenuItem.isEnabled = false
        Updater.shared.install(m) { [weak self] error in
            self?.updateMenuItem.isEnabled = true
            self?.refreshUpdateItem()
            self?.showUpdateError(error)
        }
    }

    private func showUpdateError(_ error: Error) {
        let e = AppError(wrapping: error)
        let sourceProblem = e.code == .noUpdateSource || e.code == .badUpdateSource
        let picked = ErrorReporter.shared.present(e, title: "Couldn't update PushBar",
                                                  actions: sourceProblem ? ["Set Update Source…"] : [])
        if picked == 0 { editUpdateSource() }
    }

    /// The swap script leaves a coded marker when installing an update fails
    /// and it has put the previous version back.
    private func reportFailedUpdateIfAny() {
        let marker = Updater.swapFailureMarker
        guard let text = try? String(contentsOf: marker, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: marker)
        let parts = text.split(separator: "|", maxSplits: 1).map(String.init)
        let code = parts.first.flatMap { ErrorCode(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? .updateSwapFailed
        ErrorReporter.shared.report(AppError(code, parts.count > 1 ? parts[1] : nil),
                                    surface: .alert, title: "Couldn't install the update")
    }

    private func refreshProblemItem() {
        if let p = ErrorReporter.shared.pending {
            problemMenuItem.title = "⚠️ Problem \(p.code.rawValue) — click for details"
            problemMenuItem.toolTip = ErrorReporter.tooltip
            problemMenuItem.isHidden = false
        } else {
            problemMenuItem.isHidden = true
        }
    }

    @objc private func showPendingProblem() {
        guard let p = ErrorReporter.shared.pending else { return }
        ErrorReporter.shared.clearPending()
        ErrorReporter.shared.present(p, title: "PushBar ran into a problem")
    }

    @objc private func editUpdateSource() {
        let alert = NSAlert()
        alert.messageText = "Update Source"
        alert.informativeText = "Where PushBar looks for new versions: a web link or a file path to a latest.json feed. "
            + "Leave it empty to use the built-in source"
            + (AppVersion.updateFeed.isEmpty ? " (none in this build)." : ":\n\(AppVersion.updateFeed)")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.stringValue = UserDefaults.standard.string(forKey: "updateFeed") ?? ""
        field.placeholderString = AppVersion.updateFeed.isEmpty ? "https://…/latest.json" : AppVersion.updateFeed
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty && Updater.url(from: value) == nil {
            showUpdateError(AppError(.badUpdateSource, value))
            return
        }
        Updater.shared.feed = value
        Updater.shared.check { _ in }
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/jonpikereally/Push3InterfaceControl") { NSWorkspace.shared.open(url) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
