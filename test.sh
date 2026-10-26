#!/bin/zsh
# ./test.sh             live round-trip test against the connected Push 3
#                       (run from a normal Terminal: sandboxed shells can't see
#                       audio devices). Briefly changes each level and mute,
#                       then puts it back.
# ./test.sh --snapshot <dir>   render the popover to PNGs from fake values
set -e
cd "$(dirname "$0")"
CACHE="${TMPDIR:-/tmp}/pushbar-modcache"
mkdir -p "$CACHE"
[[ -f Sources/PushBar/Version.swift ]] || ./build.sh >/dev/null
LIB=($(ls Sources/PushBar/*.swift | grep -v main.swift))
if [[ "$1" == "--snapshot" ]]; then
  swiftc -module-cache-path "$CACHE" -o "$CACHE/pushbar-snapshot" Tests/Snapshot/main.swift $LIB
  mkdir -p "${2:-$CACHE}"
  "$CACHE/pushbar-snapshot" "${2:-$CACHE}"
  exit
fi
swiftc -module-cache-path "$CACHE" -o "$CACHE/pushbar-tests" Tests/main.swift $LIB
"$CACHE/pushbar-tests"
