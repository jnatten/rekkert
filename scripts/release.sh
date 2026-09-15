#!/bin/bash
# Archives for the App Store and sends the build to TestFlight.
#
#   scripts/release.sh             # test, archive, export, validate, upload
#   scripts/release.sh --bump      # raise the build number first
#   scripts/release.sh --archive   # stop after the .ipa, upload nothing
#   scripts/release.sh --validate  # archive and validate, upload nothing
#   scripts/release.sh --skip-tests
#
# Needs, once:
#   TUIST_DEVELOPMENT_TEAM      the paid team id, in mise.local.toml
#   APP_STORE_CONNECT_KEY_ID    App Store Connect -> Users and Access ->
#   APP_STORE_CONNECT_ISSUER_ID   Integrations -> App Store Connect API, key role Developer
#   ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8   the downloaded key, kept private
#
# The watch app rides along inside the iPhone app, so this uploads both.
# Every upload needs a build number no earlier upload used: --bump, or edit Project.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

DO_TESTS=1
STOP_AFTER=upload
BUMP=0
for arg in "$@"; do
  case "$arg" in
    --bump) BUMP=1 ;;
    --archive) STOP_AFTER=archive ;;
    --validate) STOP_AFTER=validate ;;
    --skip-tests) DO_TESTS=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

OUT=.build/release
ARCHIVE="$OUT/Rekkert.xcarchive"
EXPORTED="$OUT/export"
IPA="$EXPORTED/Rekkert.ipa"

team="${TUIST_DEVELOPMENT_TEAM:-}"
if [ -z "$team" ]; then
  echo "TUIST_DEVELOPMENT_TEAM is not set. Put your paid team id in mise.local.toml." >&2
  exit 1
fi

key_id="${APP_STORE_CONNECT_KEY_ID:-}"
issuer="${APP_STORE_CONNECT_ISSUER_ID:-}"
key_path="$HOME/.appstoreconnect/private_keys/AuthKey_$key_id.p8"
if [ "$STOP_AFTER" != archive ]; then
  if [ -z "$key_id" ] || [ -z "$issuer" ]; then
    echo "Set APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID, or pass --archive." >&2
    exit 1
  fi
  if [ ! -f "$key_path" ]; then
    echo "No API key at $key_path" >&2
    exit 1
  fi
fi

auth=()
if [ -n "$key_id" ] && [ -n "$issuer" ] && [ -f "$key_path" ]; then
  auth=(-authenticationKeyPath "$key_path"
        -authenticationKeyID "$key_id"
        -authenticationKeyIssuerID "$issuer")
fi

if [ "$BUMP" = 1 ]; then
  python3 - <<'PY'
import re, pathlib
path = pathlib.Path("Project.swift")
source = path.read_text()
current = int(re.search(r'"CURRENT_PROJECT_VERSION": "(\d+)"', source).group(1))
path.write_text(re.sub(
    r'("CURRENT_PROJECT_VERSION": ")\d+(")', rf'\g<1>{current + 1}\g<2>', source, count=1
))
print(f"==> Build number {current} -> {current + 1}")
PY
fi

version=$(grep -o '"MARKETING_VERSION": "[^"]*"' Project.swift | head -1 | cut -d'"' -f4)
build=$(grep -o '"CURRENT_PROJECT_VERSION": "[^"]*"' Project.swift | head -1 | cut -d'"' -f4)
echo "==> Rekkert $version ($build), team $team"

if [ "$DO_TESTS" = 1 ]; then
  echo "==> Package tests"
  swift test --package-path Packages/RekkertKit
fi

echo "==> tuist generate"
mise exec -- tuist generate --no-open

echo "==> Archive"
rm -rf "$ARCHIVE" "$EXPORTED"
xcodebuild -workspace Rekkert.xcworkspace -scheme Rekkert \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" -quiet \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} archive

# The watch app is only in TestFlight if it is inside the thing we upload.
test -d "$ARCHIVE/Products/Applications/Rekkert.app/Watch/RekkertWatch.app" || {
  echo "FAIL: the archive has no embedded watch app"; exit 1; }

echo "==> Export"
options="$OUT/ExportOptions.plist"
cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>teamID</key><string>$team</string>
	<key>destination</key><string>export</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$options" -exportPath "$EXPORTED" -quiet \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}

test -f "$IPA" || { echo "FAIL: no .ipa at $IPA"; exit 1; }
echo "  $IPA ($(du -h "$IPA" | cut -f1))"
if [ "$STOP_AFTER" = archive ]; then exit 0; fi

# Validation catches a bad icon, a missing privacy manifest or a duplicate build number
# without spending the build number, so it always runs before the upload.
echo "==> Validate against App Store Connect"
xcrun altool --validate-app --type ios --file "$IPA" \
  --apiKey "$key_id" --apiIssuer "$issuer"
if [ "$STOP_AFTER" = validate ]; then exit 0; fi

echo "==> Upload"
xcrun altool --upload-app --type ios --file "$IPA" \
  --apiKey "$key_id" --apiIssuer "$issuer"

echo "==> Uploaded $version ($build). App Store Connect emails you when processing finishes."
