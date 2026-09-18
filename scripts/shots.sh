#!/bin/bash
# Retakes every screenshot the landing page and the App Store listing use.
#
#   scripts/shots.sh              # build, then take all of them
#   scripts/shots.sh --docs       # only the ones docs/index.html shows
#   scripts/shots.sh --store      # only the App Store set
#   scripts/shots.sh --no-build   # reuse whatever is already in .build/shots
#
# Docs images land in docs/images/ at the sizes index.html declares. App Store images
# land in fastlane/screenshots/en-US/ at the simulator's own resolution, which is where
# `scripts/release.sh --screenshots` uploads them from.
#
# Override the devices if the listing needs a different size:
#
#   REKKERT_SHOTS_PHONE="iPhone 17 Pro" scripts/shots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DO_DOCS=1
DO_STORE=1
BUILD=1
for arg in "$@"; do
  case "$arg" in
    --docs) DO_STORE=0 ;;
    --store) DO_DOCS=0 ;;
    --no-build) BUILD=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# The Pro Max is the 6.9" slot App Store Connect insists on, and the tallest iPhone
# there is — which is what gets the presets and all six ways to start into one shot.
# "Join a match" sits below the fold now that there are six of them.
PHONE_NAME=${REKKERT_SHOTS_PHONE:-"iPhone 17 Pro Max"}
WATCH_NAME=${REKKERT_SHOTS_WATCH:-"Apple Watch Ultra 3 (49mm)"}

DD=.build/shots
RAW=.build/shots/raw
STORE=fastlane/screenshots/en-US
IOS_ID=dev.natten.rekkert
WATCH_ID=dev.natten.rekkert.watchkitapp
IOS_APP="$DD/Build/Products/Debug-iphonesimulator/Rekkert.app"
WATCH_APP="$DD/Build/Products/Debug-watchsimulator/RekkertWatch.app"

# How long to let the app draw before the shutter. Raise it if a shot comes out
# on a spinner.
SETTLE=${REKKERT_SHOTS_SETTLE:-6}

udid_for() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device.get("name") == name and device.get("isAvailable"):
            print(device["udid"])
            raise SystemExit
raise SystemExit("no available simulator named %r" % name)
' "$1"
}

# Resolved before the build so both steps name the very device the shots come off, by id.
# A name alone means the newest runtime, which is where a device Apple has replaced stops
# existing — and the pixel size of these is the whole point of them.
PHONE=$(udid_for "$PHONE_NAME")
WATCH=$(udid_for "$WATCH_NAME")

if [ "$BUILD" = 1 ]; then
  echo "==> tuist generate"
  mise exec -- tuist generate --no-open >/dev/null

  echo "==> Build iOS app"
  xcodebuild -workspace Rekkert.xcworkspace -scheme Rekkert \
    -destination "id=$PHONE" \
    -derivedDataPath "$DD" -quiet build

  echo "==> Build watch app"
  xcodebuild -workspace Rekkert.xcworkspace -scheme RekkertWatch \
    -destination "id=$WATCH" \
    -derivedDataPath "$DD" -quiet build
fi

test -d "$IOS_APP" || { echo "FAIL: no iOS app at $IOS_APP — drop --no-build"; exit 1; }
test -d "$WATCH_APP" || { echo "FAIL: no watch app at $WATCH_APP — drop --no-build"; exit 1; }

echo "==> Boot $PHONE_NAME and $WATCH_NAME"
xcrun simctl bootstatus "$PHONE" -b >/dev/null
xcrun simctl bootstatus "$WATCH" -b >/dev/null

# Every shot in the set is dark, and the phone gets the status bar Apple uses in
# its own marketing. watchOS has no status bar to override, so it keeps the clock
# it happens to be showing.
xcrun simctl ui "$PHONE" appearance dark >/dev/null
xcrun simctl status_bar "$PHONE" override \
  --time "09:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charging --batteryLevel 100

mkdir -p "$RAW"

# A session outlives the app, so the home screen only turns up on a container that
# has never held one. Reinstalling before each shot is what makes these repeatable.
shoot() {
  local udid=$1 app=$2 bundle=$3 out=$4
  shift 4
  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$udid" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$app"
  xcrun simctl launch "$udid" "$bundle" "$@" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$udid" screenshot "$out" >/dev/null 2>&1
  echo "  $out"
}

# Twenty taps land on 15-15 with the games at 3-0, which is the score the landing
# page's alt text describes — and the watch and the phone agree because of it.
SCORE=(-rekkert-demo traditional -rekkert-demo-points 20)

echo "==> iPhone"
shoot "$PHONE" "$IOS_APP" "$IOS_ID" "$RAW/home.png" -rekkert-demo-presets
shoot "$PHONE" "$IOS_APP" "$IOS_ID" "$RAW/americano.png" -rekkert-demo americano -rekkert-demo-rounds
# The rounds list rather than the scoreboard: three rounds with three different
# partnerships in them is what a friendly is, and a scoreboard cannot show that.
shoot "$PHONE" "$IOS_APP" "$IOS_ID" "$RAW/friendly.png" -rekkert-demo friendly -rekkert-demo-friendly-rounds 3 -rekkert-demo-rounds-sheet
# Landscape last: the simulator stays turned until something turns it back.
shoot "$PHONE" "$IOS_APP" "$IOS_ID" "$RAW/match.png" "${SCORE[@]}" -rekkert-demo-landscape

echo "==> Apple Watch"
shoot "$WATCH" "$WATCH_APP" "$WATCH_ID" "$RAW/watch.png" "${SCORE[@]}"
shoot "$WATCH" "$WATCH_APP" "$WATCH_ID" "$RAW/watch-controls.png" "${SCORE[@]}" -rekkert-demo-watch-page controls
# The workout, counting and held. Only the counting one is shipped; the held one and the
# menu stay raw, because a stopped clock and an open menu need a sentence to explain and
# neither the page nor the listing has one to spare.
shoot "$WATCH" "$WATCH_APP" "$WATCH_ID" "$RAW/watch-workout.png" "${SCORE[@]}" -rekkert-demo-workout -rekkert-demo-watch-page workout
shoot "$WATCH" "$WATCH_APP" "$WATCH_ID" "$RAW/watch-workout-paused.png" "${SCORE[@]}" -rekkert-demo-workout-paused -rekkert-demo-watch-page workout
shoot "$WATCH" "$WATCH_APP" "$WATCH_ID" "$RAW/watch-workout-menu.png" "${SCORE[@]}" -rekkert-demo-workout-paused -rekkert-demo-watch-page menu

if [ "$DO_DOCS" = 1 ]; then
  echo "==> docs/images"
  cp "$RAW/watch.png" "$RAW/watch-controls.png" "$RAW/watch-workout.png" docs/images/
  for name in home americano friendly; do
    cp "$RAW/$name.png" "docs/images/$name.png"
    sips -z 1216 560 "docs/images/$name.png" >/dev/null
  done
  cp "$RAW/match.png" docs/images/match.png
  sips -z 552 1200 docs/images/match.png >/dev/null

  # index.html states each image's size, and a browser lays the page out from
  # those before the pixels arrive. A shot at a size it does not expect is a
  # silently crooked page, so say so rather than let it through.
  python3 - <<'PY'
import re, struct, sys, pathlib

html = pathlib.Path("docs/index.html").read_text()
declared = re.findall(r'src="(images/[^"]+)"[^>]*width="(\d+)" height="(\d+)"', html)
bad = []
for src, width, height in declared:
    data = pathlib.Path("docs").joinpath(src).read_bytes()
    actual = struct.unpack(">II", data[16:24])
    if actual != (int(width), int(height)):
        bad.append(f"  {src}: file is {actual[0]}x{actual[1]}, index.html says {width}x{height}")
if bad:
    sys.exit("FAIL: index.html and the images disagree\n" + "\n".join(bad))
print(f"  ok: {len(declared)} images match the sizes index.html declares")
PY
fi

if [ "$DO_STORE" = 1 ]; then
  echo "==> $STORE"
  # One flat folder per locale is deliver's own layout: it reads the device from each
  # image's pixel size, so the names only decide the order they appear in the listing.
  rm -rf "$STORE"
  mkdir -p "$STORE"
  cp "$RAW/home.png" "$STORE/iphone-1-home.png"
  cp "$RAW/americano.png" "$STORE/iphone-2-americano.png"
  cp "$RAW/friendly.png" "$STORE/iphone-3-friendly.png"
  cp "$RAW/match.png" "$STORE/iphone-4-match.png"
  cp "$RAW/watch.png" "$STORE/watch-1-scoreboard.png"
  cp "$RAW/watch-controls.png" "$STORE/watch-2-controls.png"
  cp "$RAW/watch-workout.png" "$STORE/watch-3-workout.png"
  # App Store Connect rejects an upload whose pixel size is not one it lists for the
  # device, and it is the only place that knows the current list — so print what came
  # out rather than assert anything about it.
  find "$STORE" -name '*.png' | sort | while read -r shot; do
    echo "  $shot  $(sips -g pixelWidth -g pixelHeight "$shot" | awk '/pixel/ {printf "%s", $2 " "}')"
  done
  echo "  upload them with: ./scripts/release.sh --screenshots"
fi

echo "==> Done"
