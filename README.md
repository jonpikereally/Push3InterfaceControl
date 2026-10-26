# PushBar

A menu bar app for macOS that controls the audio interface built into
**Ableton Push 3**, with or without Ableton Live running. Push 3 works as a
class-compliant USB interface on its own, but without Live there's nowhere to
set its levels. PushBar gives you that:

- **Master:** Push's overall output level (the one macOS's volume keys move
  when Push is the sound output).
- **Main Out** (outputs 1/2) and **Headphones:** level and mute.
- **Inputs 1/2:** gain from 0 to +20 dB, and mute.
- **Link** button on each pair: move left and right together or separately.
- **Mac Output / Mac Input:** make Push the Mac's sound output or input in one
  click.
- **Sample rate:** 44.1, 48, 88.2 or 96 kHz.
- Follows changes made elsewhere (Live, Audio MIDI Setup, Push itself) and
  notices Push being plugged in or unplugged.
- Updates itself from this repo, and every error has a code (see
  [ERRORS.md](ERRORS.md)).

PushBar only talks to Push through macOS's audio system (CoreAudio). It needs
no permissions. The only network traffic is the update check to
`raw.githubusercontent.com`.

**If Push goes dark after you quit Live:** Live puts Push to sleep on quit,
and its audio device disappears. Unplug Push's USB cable and plug it back in.

## Build and install

Command Line Tools only, no Xcode.

```bash
./install.sh
```

builds the app, copies it to `~/Applications` (apps can't run from Dropbox),
re-signs it ad-hoc and launches it.

- `./build.sh`: local build only (`PushBar.app` in this folder).
- `./test.sh`: reads every control on the connected Push, sets each one to a
  new value, checks it read back, and puts it back. Run it from a normal
  Terminal (sandboxed shells can't see audio devices). `./test.sh --snapshot
  <dir>` renders the popover to PNGs from fake values, no Push needed.
- `UPDATE_NOTES="…" ./release.sh`: universal build, writes `updates/PushBar.zip`
  and `updates/latest.json`; commit and push `updates/` to ship.

## How it works

| File | What it does |
|---|---|
| `Push.swift` | Finds Push 3 in CoreAudio, mirrors its volume/mute controls with property listeners, writes changes |
| `ContentView.swift` | The popover, plus the link settings |
| `main.swift` | Menu bar item and menu |
| `Updater.swift`, `Errors.swift` | Self-updater and coded errors (same pattern as PasteStack and MixBar) |

Push 3's controls as macOS sees them (firmware as of Oct 2026): output element
0 is Master, 1/2 Analog Out L/R, 3/4 Headphones L/R (−90 to +6 dB, mute on
1–4); input elements 1/2 are Analog In L/R (0 to +20 dB gain, mute). PushBar
looks these up by element name and falls back to those numbers.
