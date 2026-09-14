#!/bin/bash
# Builds for real hardware and installs onto your paired iPhone and Apple Watch.
#
#   scripts/deploy.sh              # build, install both, launch on the phone
#   scripts/deploy.sh --release    # same, Release configuration
#   scripts/deploy.sh --phone      # iPhone only
#   scripts/deploy.sh --watch      # Apple Watch only
#   scripts/deploy.sh --no-launch  # install without opening anything
#   scripts/deploy.sh --check      # just report what is installed on each device
#
# Needs TUIST_DEVELOPMENT_TEAM set (mise.local.toml). Both devices must be
# unlocked, and the watch on the same Wi-Fi as this Mac if it is not tethered.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=Debug
DO_PHONE=1
DO_WATCH=1
LAUNCH=1
CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --release) CONFIG=Release ;;
    --debug) CONFIG=Debug ;;
    --phone) DO_WATCH=0 ;;
    --watch) DO_PHONE=0 ;;
    --no-launch) LAUNCH=0 ;;
    --check) CHECK_ONLY=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

DD=.build/device
APP="$DD/Build/Products/$CONFIG-iphoneos/Rekkert.app"
WATCH_APP="$APP/Watch/RekkertWatch.app"
IOS_ID=dev.natten.rekkert
WATCH_ID=dev.natten.rekkert.watchkitapp

devices=$(mktemp -t rekkert-devices)
trap 'rm -f "$devices"' EXIT
xcrun devicectl list devices --quiet --json-output "$devices"

# First paired device of each kind, so there is nothing to configure by hand.
find_device() {
  python3 - "$devices" "$1" <<'PY'
import json, sys
for device in json.load(open(sys.argv[1]))["result"]["devices"]:
    if device["hardwareProperties"]["platform"] == sys.argv[2]:
        print(device["identifier"], device["deviceProperties"].get("name", "?"), sep="\t")
        break
PY
}

phone=$(find_device iOS)
watch=$(find_device watchOS)

if [ "$DO_PHONE" = 1 ] && [ -z "$phone" ]; then
  echo "No paired iPhone found. Plug it in, or check Wi-Fi pairing." >&2
  exit 1
fi
if [ "$DO_WATCH" = 1 ] && [ -z "$watch" ]; then
  echo "No paired Apple Watch found. Unlock it and put it on this Mac's network." >&2
  exit 1
fi

id_of() { printf '%s' "${1%%$'\t'*}"; }
name_of() { printf '%s' "${1#*$'\t'}"; }

installed() {
  xcrun devicectl device info apps --device "$(id_of "$1")" --bundle-id "$2" 2>/dev/null \
    | awk -v id="$2" '$2 == id { print $NF }'
}

report() {
  local found
  found=$(installed "$1" "$2")
  echo "  $(name_of "$1"): ${found:-not installed}"
}

if [ "$CHECK_ONLY" = 1 ]; then
  echo "==> Installed builds"
  [ "$DO_PHONE" = 1 ] && report "$phone" "$IOS_ID"
  [ "$DO_WATCH" = 1 ] && report "$watch" "$WATCH_ID"
  exit 0
fi

echo "==> tuist generate"
mise exec -- tuist generate --no-open

build() {
  xcodebuild -workspace Rekkert.xcworkspace -scheme Rekkert \
    -configuration "$CONFIG" \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DD" \
    -allowProvisioningUpdates \
    -quiet build
}

echo "==> Build $CONFIG for device (embeds the watch app)"
# The first device build of the day can fail on a profile it is downloading as it
# reads it. Once it is on disk a second attempt goes straight through.
build || { echo "==> Retrying after provisioning refresh"; build; }

test -d "$APP" || { echo "FAIL: no app at $APP" >&2; exit 1; }
version=$(plutil -extract CFBundleVersion raw "$APP/Info.plist")
echo "==> Built $(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist") ($version)"

# A device that has locked itself since the listing drops the install service with
# a CoreDeviceError 3002. Waking it and going again is all it takes.
install_to() {
  local id name
  id=$(id_of "$1")
  name=$(name_of "$1")
  echo "==> Install onto $name"
  if ! xcrun devicectl device install app --device "$id" "$2" >/dev/null 2>&1; then
    echo "    first attempt failed - unlock $name if it is asleep, retrying"
    sleep 3
    xcrun devicectl device install app --device "$id" "$2" >/dev/null
  fi
}

[ "$DO_PHONE" = 1 ] && install_to "$phone" "$APP"
# The watch app rides along inside the iOS app, but pushing it straight to the
# watch beats waiting for the Watch app on the phone to notice.
[ "$DO_WATCH" = 1 ] && install_to "$watch" "$WATCH_APP"

if [ "$LAUNCH" = 1 ] && [ "$DO_PHONE" = 1 ]; then
  echo "==> Launch on $(name_of "$phone")"
  xcrun devicectl device process launch --device "$(id_of "$phone")" "$IOS_ID" >/dev/null
fi

echo "==> On the devices now:"
[ "$DO_PHONE" = 1 ] && report "$phone" "$IOS_ID"
[ "$DO_WATCH" = 1 ] && report "$watch" "$WATCH_ID"
