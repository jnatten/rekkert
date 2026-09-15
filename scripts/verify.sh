#!/bin/bash
# Full verification: engine tests, project generation, both app builds,
# and an assertion that the watch app is embedded and configured correctly.
set -euo pipefail
cd "$(dirname "$0")/.."

DD=.build/dd
APP="$DD/Build/Products/Debug-iphonesimulator/Rekkert.app"
WATCH_APP="$APP/Watch/RekkertWatch.app"

echo "==> Package tests (macOS, no simulator)"
swift test --package-path Packages/RekkertKit

echo "==> tuist generate"
mise exec -- tuist generate --no-open

echo "==> Build iOS app (embeds watch app)"
xcodebuild -workspace Rekkert.xcworkspace -scheme Rekkert \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath "$DD" -quiet build

echo "==> Build watch app"
xcodebuild -workspace Rekkert.xcworkspace -scheme RekkertWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
  -derivedDataPath "$DD" -quiet build

echo "==> Assert watch app is embedded and configured"
test -d "$WATCH_APP" || { echo "FAIL: watch app not embedded at $WATCH_APP"; exit 1; }
plist="$WATCH_APP/Info.plist"
check() {
  plutil -p "$plist" | grep -q "$1" || { echo "FAIL: expected $1 in watch Info.plist"; exit 1; }
  echo "  ok: $1"
}
check '"WKApplication" => true'
check '"WKCompanionAppBundleIdentifier" => "dev.natten.rekkert"'
check '"CFBundleIdentifier" => "dev.natten.rekkert.watchkitapp"'

echo "==> Assert the iPhone app may look at the local network"
# Without these two, sharing a match fails at runtime with nothing in the UI to explain it.
iosplist="$APP/Info.plist"
check_ios() {
  plutil -p "$iosplist" | grep -q "$1" || { echo "FAIL: expected $1 in iOS Info.plist"; exit 1; }
  echo "  ok: $1"
}
check_ios 'NSLocalNetworkUsageDescription'
check_ios 'NSBonjourServices'
check_ios '"_rekkert-score._tcp"'

echo "==> All checks passed"
