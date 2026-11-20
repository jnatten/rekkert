#!/bin/bash
# Taps each way into the pairing rule sheet on a simulator and says whether the sheet stays up.
#
#   .specify/bugs/pairing-rule-sheet-closes/repro.sh <simulator-udid> <path/to/Rekkert.app>
#
# Needs a Debug build (the launch flags are debug-only) and `axe` (brew install cameroncooke/axe/axe).
# Use a simulator nothing else is driving: the app is reinstalled, with its data wiped, for every case.
set -uo pipefail

UDID=${1:?simulator udid}
APP=${2:?path to a Debug-iphonesimulator Rekkert.app}
BUNDLE=dev.natten.rekkert
OUT=${TMPDIR:-/tmp}/pairing-rule-sheet-closes
mkdir -p "$OUT"

xcrun simctl bootstatus "$UDID" -b >/dev/null

on_screen() {
  axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c '
import json, sys
labels = []
def walk(node):
    if node.get("type") in ("Heading", "Button") and node.get("AXLabel"):
        labels.append(node["AXLabel"])
    for child in node.get("children") or []:
        walk(child)
for node in json.load(sys.stdin):
    walk(node)
print("\n".join(labels))'
}

failures=0
check() {
  local name=$1 tap=$2 expect=$3
  shift 3
  xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep 6
  xcrun simctl spawn "$UDID" log stream --level default --style compact \
    --predicate 'process == "Rekkert" AND subsystem == "com.apple.UIKit"' >"$OUT/$name.log" 2>&1 &
  local logger=$!
  sleep 2
  if ! axe tap --label "$tap" --element-type Button --wait-timeout 5 --udid "$UDID" >/dev/null 2>&1; then
    kill "$logger"
    echo "SKIP $name: no \"$tap\" button on screen"
    failures=$((failures + 1))
    return
  fi
  sleep 3
  kill "$logger"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
  local extra
  extra=$(grep -c 'which is already presenting' "$OUT/$name.log")
  if on_screen | grep -qx "$expect"; then
    echo "PASS $name: \"$expect\" is still up ($extra extra presentations logged)"
  else
    echo "FAIL $name: \"$expect\" is gone, screen shows: $(on_screen | head -3 | paste -sd '|' -) ($extra extra presentations logged)"
    failures=$((failures + 1))
  fi
}

players=(-rekkert-demo-new friendly -rekkert-demo-new-players Ada,Bob,Cy,Dan,Eve)
check setup-apart "Keep players apart…" "Keep apart" "${players[@]}"
check setup-together "Keep two together…" "Keep together" "${players[@]}"
check setup-with-rule "Keep players apart…" "Keep apart" "${players[@]}" -rekkert-demo-new-apart 2
check inplay-apart "Keep players apart…" "Keep apart" -rekkert-demo friendly -rekkert-demo-pairing-rules

echo "screenshots and logs in $OUT"
exit $((failures > 0))
