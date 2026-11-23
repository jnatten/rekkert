#!/bin/bash
# The watch's board, looked at while the app is stopped in the middle of whatever it was doing.
#
#   scripts/board-at-rest.sh              # build, then look
#   scripts/board-at-rest.sh --no-build   # reuse whatever is already in .build/dd
#
# The app draws an animation frame by frame. A watch that stops drawing part way through one
# goes on showing the in-between frame: a number that is a blur, or two rounds' names on top of
# each other (bug shared-guest-half-board). So nothing on the watch's board animates, and this
# checks it the only way a simulator can: an Americano plays itself, the app's process is
# stopped at arbitrary moments, and a second later every half of the board has to have its
# number.
#
# Not part of verify.sh, which boots no simulator. Override the watch or how often it is stopped:
#
#   REKKERT_BOARD_WATCH="Apple Watch SE 3 (40mm)" REKKERT_BOARD_STOPS=60 scripts/board-at-rest.sh
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=1
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

WATCH_NAME=${REKKERT_BOARD_WATCH:-"Apple Watch Ultra 3 (49mm)"}
STOPS=${REKKERT_BOARD_STOPS:-30}

DD=.build/dd
WATCH_APP="$DD/Build/Products/Debug-watchsimulator/RekkertWatch.app"
WATCH_ID=dev.natten.rekkert.watchkitapp
SHOTS=.build/board-at-rest-shots
CHECK=.build/board-at-rest

WATCH=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device.get("name") == name and device.get("isAvailable"):
            print(device["udid"])
            raise SystemExit
raise SystemExit("no available simulator named %r" % name)
' "$WATCH_NAME")

if [ "$BUILD" = 1 ]; then
  echo "==> tuist generate"
  mise exec -- tuist generate --no-open >/dev/null
  echo "==> Build watch app"
  xcodebuild -workspace Rekkert.xcworkspace -scheme RekkertWatch \
    -destination "id=$WATCH" \
    -derivedDataPath "$DD" -quiet build
fi
test -d "$WATCH_APP" || { echo "FAIL: no watch app at $WATCH_APP — drop --no-build"; exit 1; }

mkdir -p .build
swiftc -O -o "$CHECK" scripts/board-at-rest.swift

echo "==> Boot $WATCH_NAME"
xcrun simctl bootstatus "$WATCH" -b >/dev/null

rm -rf "$SHOTS"
mkdir -p "$SHOTS"
xcrun simctl terminate "$WATCH" "$WATCH_ID" >/dev/null 2>&1 || true
xcrun simctl install "$WATCH" "$WATCH_APP"

echo "==> An Americano playing itself, stopped $STOPS times"
PID=$(xcrun simctl launch "$WATCH" "$WATCH_ID" \
  -rekkert-demo americano -rekkert-demo-courts 2 -rekkert-demo-live 80 | awk '{ print $NF }')
# Left stopped, the app would sit on the simulator until somebody killed it.
trap 'kill -CONT "$PID" 2>/dev/null || true; xcrun simctl terminate "$WATCH" "$WATCH_ID" >/dev/null 2>&1 || true' EXIT
sleep 5

for stop in $(seq -w 1 "$STOPS"); do
  sleep "0.$(( RANDOM % 6 + 3 ))"
  kill -STOP "$PID"
  # Twice as long as the longest animation there has been on this board.
  sleep 1
  xcrun simctl io "$WATCH" screenshot "$SHOTS/$stop.png" >/dev/null 2>&1
  kill -CONT "$PID"
done

echo "==> Assert every half has its number"
"$CHECK" "$SHOTS"/*.png || { echo "FAIL: the board was caught part way through a change — see $SHOTS"; exit 1; }
echo "==> The board was at rest every time"
