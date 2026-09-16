#!/bin/bash
# Archives for the App Store and sends the build to TestFlight.
#
#   scripts/release.sh             # test, archive, export, validate, upload
#   scripts/release.sh --bump      # raise the build number first
#   scripts/release.sh --archive   # stop after the .ipa, upload nothing
#   scripts/release.sh --validate  # archive and validate, upload nothing
#   scripts/release.sh --skip-tests
#   scripts/release.sh --screenshots   # upload only the screenshots, build nothing
#
# Needs, once:
#   TUIST_DEVELOPMENT_TEAM      the paid team id, in mise.local.toml
#   APP_STORE_CONNECT_KEY_ID    App Store Connect -> Users and Access ->
#   APP_STORE_CONNECT_ISSUER_ID   Integrations -> App Store Connect API, team key
#   ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8   the downloaded key, kept private
#
# The key's role must be Admin. Export asks App Store Connect for a cloud-managed
# distribution certificate, and that is restricted to Account Holders and Admins: a
# Developer key is refused with a 403 and the export ends up with nothing to sign with,
# reported as the unrelated-looking "No signing certificate iOS Distribution found".
# A key's role cannot be changed afterwards, so a wrong one has to be replaced.
#
# The watch app rides along inside the iPhone app, so this uploads both.
# Every upload needs a build number no earlier upload used: --bump, or edit Project.swift.
#
# --screenshots uploads whatever `scripts/shots.sh` last put in fastlane/screenshots/.
# Screenshots belong to a version rather than to the app, so this needs a version in an
# editable state — the one you are preparing. It replaces the whole set for each device
# size rather than adding to it, because App Store Connect caps a set at ten and then
# starts refusing.
set -euo pipefail
cd "$(dirname "$0")/.."

# Export shells out to /usr/bin/rsync, which is Apple's openrsync, and openrsync starts a
# second rsync off PATH to copy to. Homebrew's rsync is not Apple's and rejects the -E it
# is handed, which surfaces three steps later as a bare "Copy failed" with nothing in it
# about rsync. /usr/bin first keeps the pair matched; mise and tuist are still found.
export PATH="/usr/bin:$PATH"

DO_TESTS=1
STOP_AFTER=upload
BUMP=0
for arg in "$@"; do
  case "$arg" in
    --bump) BUMP=1 ;;
    --archive) STOP_AFTER=archive ;;
    --validate) STOP_AFTER=validate ;;
    --skip-tests) DO_TESTS=0 ;;
    --screenshots) STOP_AFTER=screenshots ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

IOS_ID=dev.natten.rekkert
OUT=.build/release
ARCHIVE="$OUT/Rekkert.xcarchive"
EXPORTED="$OUT/export"
IPA="$EXPORTED/Rekkert.ipa"

team="${TUIST_DEVELOPMENT_TEAM:-}"
if [ -z "$team" ] && [ "$STOP_AFTER" != screenshots ]; then
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

if [ "$STOP_AFTER" = screenshots ]; then
  shots=fastlane/screenshots
  test -n "$(find "$shots" -name '*.png' 2>/dev/null)" || {
    echo "No screenshots in $shots/ - run ./scripts/shots.sh first" >&2; exit 1; }

  # deliver wants the key as one JSON file rather than as the three separate things every
  # other Apple tool takes. It carries the private key, so it is written where only this
  # user can read it and removed on the way out however the script ends.
  api_key=$(mktemp -t rekkert-asc-key)
  trap 'rm -f "$api_key"' EXIT
  chmod 600 "$api_key"
  KEY_ID="$key_id" ISSUER="$issuer" KEY_PATH="$key_path" python3 -c '
import json, os, pathlib
print(json.dumps({
    "key_id": os.environ["KEY_ID"],
    "issuer_id": os.environ["ISSUER"],
    "key": pathlib.Path(os.environ["KEY_PATH"]).read_text(),
    "in_house": False,
}))' > "$api_key"

  echo "==> Upload screenshots"
  find "$shots" -name '*.png' | sort | sed 's/^/  /'
  # --force skips the HTML summary deliver would otherwise stop and ask you to confirm.
  mise exec -- fastlane deliver \
    --api_key_path "$api_key" \
    --app_identifier "$IOS_ID" \
    --screenshots_path "$shots" \
    --skip_binary_upload true \
    --skip_metadata true \
    --skip_screenshots false \
    --overwrite_screenshots true \
    --force true
  echo "==> Screenshots uploaded, onto the version you are preparing."
  exit 0
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
