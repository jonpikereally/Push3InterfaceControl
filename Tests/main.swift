import AppKit

// Live round-trip test against the connected Push 3: every control is set to
// a new value, read back, and put back. Run ./test.sh from a normal Terminal.
_ = NSApplication.shared
let push = Push.shared
push.start()
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
guard push.connected else { print("FAIL: Push 3 isn't connected (PB-201)"); exit(1) }
print("Push 3 found (device \(push.device!)), \(push.sampleRate) Hz, rates \(push.sampleRates)")
print("Mac output: \(push.isMacOutput), Mac input: \(push.isMacInput)")

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "ok  " : "FAIL") \(what)")
    if !ok { failures += 1 }
}

for strip in Strip.allCases {
    let before = push.channels(strip)
    print("\(strip.rawValue): " + before.map { String(format: "%.3f (%.1f dB)%@", $0.scalar, $0.db, $0.mute ? " muted" : "") }
        .joined(separator: ", "))
    check(!before.isEmpty, "\(strip.rawValue) has controls")
    for (i, ch) in before.enumerated() {
        let target = ch.scalar > 0.5 ? 0.25 : 0.75
        push.setVolume(strip, side: i, scalar: target)
        let got = push.channels(strip)[i].scalar
        check(abs(got - target) < 0.02, "\(strip.rawValue)[\(i)] volume → \(target), read back \(String(format: "%.3f", got))")
        // The other side must not move when setting one.
        if before.count > 1 {
            let other = 1 - i
            check(abs(push.channels(strip)[other].scalar - before[other].scalar) < 0.02, "\(strip.rawValue)[\(other)] untouched")
        }
        push.setVolume(strip, side: i, scalar: ch.scalar)
        if ch.hasMute {
            push.setMute(strip, side: i, !ch.mute)
            check(push.channels(strip)[i].mute == !ch.mute, "\(strip.rawValue)[\(i)] mute → \(!ch.mute)")
            push.setMute(strip, side: i, ch.mute)
        }
    }
    let after = push.channels(strip)
    check(zip(before, after).allSatisfy { abs($0.scalar - $1.scalar) < 0.01 && $0.mute == $1.mute }, "\(strip.rawValue) restored")
}

// Linked write moves both sides.
if let main = push.channels[.main], main.count == 2 {
    push.setVolume(.main, scalar: 0.3)
    check(push.channels(.main).allSatisfy { abs($0.scalar - 0.3) < 0.02 }, "linked main moves both sides")
    for (i, ch) in main.enumerated() { push.setVolume(.main, side: i, scalar: ch.scalar) }
}
print(failures == 0 ? "All passed." : "\(failures) failed.")
exit(failures == 0 ? 0 : 1)
