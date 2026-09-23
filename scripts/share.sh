#!/bin/bash
# Two iPhones and an Apple Watch, all simulated, on one shared match.
#
#   scripts/share.sh              # build, then run the whole thing
#   scripts/share.sh --no-build   # reuse whatever is already in .build/dd
#   scripts/share.sh --keep       # leave the simulators booted to poke at
#
# The host opens a match on a pinned code and the guest joins it without a tap, which is
# what `-rekkert-share-host` and `-rekkert-share-join` are for. Convergence is asserted on
# the event log each device writes to `active.json` rather than on the screen, so a drifting
# score fails the script instead of waiting to be noticed in a screenshot.
#
# Two phases: everybody agrees while they are all there, and then the guest is killed, the
# host scores while it is away, and the guest comes back and catches up from the log.
#
# What this cannot test, and there is no rigging that fixes it:
#   - Bluetooth. The simulator has no bluetoothd; CoreBluetooth's XPC connection is refused,
#     so `BluetoothTransport` is inert and only the local network carries anything here.
#   - A phone in a pocket. The simulator does not suspend a backgrounded app, so its listener
#     and its sockets stay up — which is the one condition the Bluetooth link exists for.
# Both of those need two real devices.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=1
KEEP=0
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    --keep) KEEP=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

HOST_NAME=${REKKERT_SHARE_HOST:-"iPhone 17 Pro"}
GUEST_NAME=${REKKERT_SHARE_GUEST:-"iPhone Air"}
CODE=${REKKERT_SHARE_CODE:-482915}

DD=.build/dd
IOS_APP="$DD/Build/Products/Debug-iphonesimulator/Rekkert.app"
WATCH_APP="$DD/Build/Products/Debug-watchsimulator/RekkertWatch.app"
IOS_ID=dev.natten.rekkert
WATCH_ID=dev.natten.rekkert.watchkitapp
SHOTS=.build/share

# The watch is looked up from the pairing rather than named, because WatchConnectivity only
# runs between the two simulators Xcode has actually paired.
read -r HOST WATCH < <(xcrun simctl list pairs -j | python3 -c '
import json, sys
name = sys.argv[1]
for pair in json.load(sys.stdin)["pairs"].values():
    if pair["phone"]["name"] == name:
        print(pair["phone"]["udid"], pair["watch"]["udid"])
        raise SystemExit
raise SystemExit("no simulator pair with a phone named %r — pair one in Xcode" % name)
' "$HOST_NAME")

GUEST=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device.get("name") == name and device.get("isAvailable"):
            print(device["udid"])
            raise SystemExit
raise SystemExit("no available simulator named %r" % name)
' "$GUEST_NAME")

if [ "$BUILD" = 1 ]; then
  echo "==> tuist generate"
  mise exec -- tuist generate --no-open >/dev/null
  echo "==> Build iOS app"
  xcodebuild -workspace Rekkert.xcworkspace -scheme Rekkert \
    -destination "id=$HOST" -derivedDataPath "$DD" -quiet build
  echo "==> Build watch app"
  xcodebuild -workspace Rekkert.xcworkspace -scheme RekkertWatch \
    -destination "id=$WATCH" -derivedDataPath "$DD" -quiet build
fi

test -d "$IOS_APP" || { echo "FAIL: no iOS app at $IOS_APP — drop --no-build"; exit 1; }
test -d "$WATCH_APP" || { echo "FAIL: no watch app at $WATCH_APP — drop --no-build"; exit 1; }

echo "==> Boot $HOST_NAME, $GUEST_NAME and the paired watch"
for device in "$HOST" "$GUEST" "$WATCH"; do xcrun simctl bootstatus "$device" -b >/dev/null; done

echo "==> Install, on containers with no session in them"
install_fresh() {
  xcrun simctl terminate "$1" "$3" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$1" "$3" >/dev/null 2>&1 || true
  xcrun simctl install "$1" "$2"
}
install_fresh "$HOST" "$IOS_APP" "$IOS_ID"
install_fresh "$GUEST" "$IOS_APP" "$IOS_ID"
install_fresh "$WATCH" "$WATCH_APP" "$WATCH_ID"

# Every event id on a device, as `device:seq`, sorted. Two devices on the same match hold the
# same set — merging is a union by event id, so anything else is a real divergence.
events_on() {
  local container
  container=$(xcrun simctl get_app_container "$1" "$2" data)
  python3 - "$container" <<'PY'
import json, sys, os
path = os.path.join(sys.argv[1], "Library/Application Support/Rekkert/active.json")
if not os.path.exists(path):
    raise SystemExit("no active session on this device")
events = json.load(open(path))["log"]["events"]
print(" ".join(sorted(f'{e["id"]["device"]["raw"][:8]}:{e["id"]["seq"]}' for e in events)))
PY
}

agree() {
  local phase=$1 host guest watch
  host=$(events_on "$HOST" "$IOS_ID")
  guest=$(events_on "$GUEST" "$IOS_ID")
  watch=$(events_on "$WATCH" "$WATCH_ID")
  local count
  count=$(wc -w <<<"$host" | tr -d ' ')
  for pair in "guest:$guest" "watch:$watch"; do
    if [ "${pair#*:}" != "$host" ]; then
      echo "FAIL ($phase): the ${pair%%:*} does not hold the host's match"
      echo "  host:  $host"
      echo "  ${pair%%:*}: ${pair#*:}"
      exit 1
    fi
  done
  echo "  ok ($phase): all three hold the same $count events"
}

shoot() { xcrun simctl io "$1" screenshot "$SHOTS/$2.png" >/dev/null 2>&1; }
mkdir -p "$SHOTS"

# The host scores once, on its own, forty seconds in. It is the only way to make a live
# update happen on a device nothing can tap — and it lands while the guest is killed.
LATE=40

echo "==> Host opens a match on $CODE, guest joins it, watch comes along"
xcrun simctl launch "$HOST" "$IOS_ID" \
  -rekkert-demo traditional -rekkert-demo-points 5 \
  -rekkert-share-host "$CODE" -rekkert-demo-late-tap "$LATE" >/dev/null
sleep 3
xcrun simctl launch "$GUEST" "$IOS_ID" -rekkert-share-join "$CODE" >/dev/null
xcrun simctl launch "$WATCH" "$WATCH_ID" >/dev/null
sleep 15
for shot in "$HOST:host" "$GUEST:guest" "$WATCH:watch"; do shoot "${shot%%:*}" "joined-${shot#*:}"; done
agree joined

echo "==> Guest drops off the network"
xcrun simctl terminate "$GUEST" "$IOS_ID" >/dev/null
sleep $((LATE - 10))

echo "==> Guest comes back to a score it never saw"
xcrun simctl launch "$GUEST" "$IOS_ID" -rekkert-share-join "$CODE" >/dev/null
sleep 15
for shot in "$HOST:host" "$GUEST:guest" "$WATCH:watch"; do shoot "${shot%%:*}" "rejoined-${shot#*:}"; done
agree rejoined

echo "==> Screenshots in $SHOTS"
if [ "$KEEP" = 0 ]; then
  for device in "$HOST" "$GUEST" "$WATCH"; do xcrun simctl shutdown "$device" >/dev/null; done
fi
