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

echo "==> Assert the watch may record a workout"
# The plist is written out by hand rather than generated, because WKBackgroundModes is an
# array and has no INFOPLIST_KEY_ of its own. These are the keys that buys, and the three
# above are the ones the generator used to supply — all of them silently absent if the
# dictionary in Project.swift loses a line.
check '"workout-processing"'
check 'NSHealthShareUsageDescription'
check 'NSHealthUpdateUsageDescription'

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
check_ios '"ITSAppUsesNonExemptEncryption" => false'
check_ios 'NSHealthShareUsageDescription'
check_ios 'NSHealthUpdateUsageDescription'

echo "==> Assert the watch app carries the same version as the iPhone app"
# The watch app used to generate its own plist and so could not drift. Now that it is
# written out, a forgotten $(MARKETING_VERSION) pins it at 1.0 (1) — which App Store Connect
# rejects by email an hour after the upload.
for key in CFBundleShortVersionString CFBundleVersion; do
  ios=$(plutil -extract "$key" raw -o - "$iosplist")
  watch=$(plutil -extract "$key" raw -o - "$plist")
  test "$ios" = "$watch" || { echo "FAIL: $key is $watch on the watch, $ios on the phone"; exit 1; }
  echo "  ok: $key matches ($ios)"
done

echo "==> Assert both apps may talk to Health"
# Checked where Tuist writes them rather than on the signed bundle: a simulator build with no
# team signs ad-hoc, and the entitlements it applies live in a -Simulated.xcent that codesign
# does not report. These files are what feed both, so a dropped line in Project.swift is
# caught here whether or not anybody has a team set.
for entitlements in Derived/Entitlements/Rekkert.entitlements Derived/Entitlements/RekkertWatch.entitlements; do
  test -f "$entitlements" || { echo "FAIL: no entitlements at $entitlements"; exit 1; }
  plutil -p "$entitlements" | grep -q '"com.apple.developer.healthkit" => true' \
    || { echo "FAIL: no HealthKit entitlement in $entitlements"; exit 1; }
  echo "  ok: HealthKit entitlement in $(basename "$entitlements")"
done

# healthkit here would delist the app from every iPad, and this one ships for iPad too.
if plutil -p "$iosplist" | grep -A5 UIRequiredDeviceCapabilities | grep -qi healthkit; then
  echo "FAIL: healthkit in UIRequiredDeviceCapabilities takes the app off every iPad"
  exit 1
fi
echo "  ok: healthkit is not a required capability"

echo "==> Assert both apps ship a privacy manifest"
# App Store Connect rejects an upload that uses UserDefaults without declaring a reason,
# and the failure arrives by email long after the build. Both bundles carry the sources
# that touch it, so both need the file — and it has to reach the bundle root.
for manifest in "$APP/PrivacyInfo.xcprivacy" "$WATCH_APP/PrivacyInfo.xcprivacy"; do
  test -f "$manifest" || { echo "FAIL: no privacy manifest at $manifest"; exit 1; }
  plutil -p "$manifest" | grep -q 'NSPrivacyAccessedAPICategoryUserDefaults' \
    || { echo "FAIL: $manifest does not declare UserDefaults"; exit 1; }
  echo "  ok: ${manifest#"$APP/"}"
done

echo "==> All checks passed"
