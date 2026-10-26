import AppKit
import SwiftUI

// Renders the popover to PNGs from fake values, so the look can be checked
// without a Push connected. ./test.sh --snapshot <dir>
let out = URL(fileURLWithPath: CommandLine.arguments[1])
_ = NSApplication.shared
let push = Push.shared
func ch(_ s: Double, _ db: Double, mute: Bool = false, hasMute: Bool = true) -> Push.Channel {
    Push.Channel(scalar: s, db: db, mute: mute, hasMute: hasMute)
}

@MainActor func render(_ name: String) {
    let r = ImageRenderer(content: ContentView(actions: MenuActions()))
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("render failed: \(name)"); return
    }
    try! png.write(to: out.appendingPathComponent(name))
    print("wrote \(name)")
}
MainActor.assumeIsolated {
    render("popover-disconnected.png")
    push.device = 1
    push.sampleRate = 44100
    push.sampleRates = [44100, 48000, 88200, 96000]
    push.isMacOutput = true
    push.channels = [.master: [ch(0.76, -6.0, hasMute: false)],
                     .main: [ch(0.84, -1.9), ch(0.84, -1.9)],
                     .phones: [ch(0.77, -5.6), ch(0.77, -5.6)],
                     .inputs: [ch(0.5, 10), ch(0.25, 5, mute: true)]]
    Prefs.shared.unlinked = []
    render("popover.png")
    Prefs.shared.unlinked = ["phones", "inputs"]
    ProblemBanner.shared.error = AppError(.setFailed, "phones volume, element 3: OSStatus 'nope' (1852797029)")
    render("popover-unlinked-banner.png")
    Prefs.shared.unlinked = []
}
