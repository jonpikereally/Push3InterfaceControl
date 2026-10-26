#!/bin/zsh
# Build PushBar and install it to ~/Applications, then launch it. Run from
# Terminal: apps can't run from inside Dropbox, and Claude's sandbox can't
# write to ~/Applications.
set -e
cd "$(dirname "$0")"
fail() {
  echo
  echo "Error $1: $2"
  echo "Look up this code on the PushBar error list:"
  echo "  https://github.com/jonpikereally/Push3InterfaceControl/blob/main/ERRORS.md"
  exit 1
}
./build.sh
APP="$HOME/Applications/PushBar.app"
pkill -x PushBar 2>/dev/null || true
sleep 0.5
mkdir -p ~/Applications || fail PB-601 "Couldn't create ~/Applications."
rm -rf "$APP"
ditto --norsrc PushBar.app "$APP" || fail PB-601 "Couldn't copy PushBar into ~/Applications."
# Sign outside Dropbox, after stripping xattrs, so the sync client can't slip any in between.
xattr -cr "$APP"
codesign --force --sign - "$APP" || fail PB-602 "Couldn't sign PushBar for this Mac."
open "$APP" || fail PB-603 "PushBar was installed but couldn't be opened. Open it from ~/Applications yourself."
echo "Installed $APP"
echo "Look for the pad-grid icon in your menu bar."
