#!/bin/bash
# Plays a tournament log back and forth between this build and older ones, as phones on different
# builds would. The newer build draws 15 rounds; each older build folds them, then draws a round
# and redraws it around a picked sit-out; the newer build folds that and draws five more; the older
# build folds the lot. Every fold must give the very rounds the other build made, in Americano and
# in Mexicano. Builds are exported from history with jj into Packages/RekkertKit/.build/, so the
# working copy is never touched. Works for builds from 25 September 2026 on, when sit-outs could
# first be picked.
#
#   scripts/cross-build.sh [--players N] [--new REV] OLD_REV...
#
# --new defaults to the working copy (@) and --players to 9.
set -euo pipefail
cd "$(dirname "$0")/.."

players=9
new=@
while [[ $# -gt 0 ]]; do
  case $1 in
    --players) players=$2; shift 2 ;;
    --new) new=$2; shift 2 ;;
    *) break ;;
  esac
done
[[ $# -gt 0 ]] || { echo "usage: $0 [--players N] [--new REV] OLD_REV..." >&2; exit 2; }

work=Packages/RekkertKit/.build/cross-build
mkdir -p "$work"
work=$(cd "$work" && pwd)

export_build() {
  local rev=$1 id dest
  id=$(jj log -r "$rev" --no-graph -T 'commit_id.short(8)')
  dest=$work/builds/$id
  if [[ ! -d $dest/Sources ]]; then
    rm -rf "$dest"
    for f in $(jj file list -r "$rev" Packages/RekkertKit/Package.swift 'glob:Packages/RekkertKit/Sources/**'); do
      mkdir -p "$dest/$(dirname "${f#Packages/RekkertKit/}")"
      jj file show -r "$rev" "$f" > "$dest/${f#Packages/RekkertKit/}"
    done
  fi
  rm -rf "$dest/Tests"
  mkdir -p "$dest/Tests/RekkertCoreTests" "$dest/Tests/RekkertSyncTests"
  echo 'import Testing' > "$dest/Tests/RekkertCoreTests/Empty.swift"
  cp scripts/cross-build/CrossBuild.swift "$dest/Tests/RekkertSyncTests/"
  echo "$id"
}

failed=0
run() {
  local id=$1; shift
  local out
  out=$(cd "$work/builds/$id" && env XVER_BUILD="$id" XVER_PLAYERS="$players" "$@" swift test --filter CrossBuild 2>&1) || failed=1
  grep -E "XVER|error:" <<< "$out" || true
  grep -q "Test run with 1 test in 1 suite passed" <<< "$out" || failed=1
}

newid=$(export_build "$new")
for rev in "$@"; do
  oldid=$(export_build "$rev")
  dir=$work/logs/$newid-$oldid-$players
  rm -rf "$dir"; mkdir -p "$dir"
  echo "==> $newid against $oldid, $players players on two courts"
  run "$newid" XVER_DIR="$dir" XVER_ACTION=record XVER_TO=A
  run "$oldid" XVER_DIR="$dir" XVER_ACTION=continue XVER_FROM=A XVER_TO=B XVER_ROUNDS=1 XVER_DEVICE=2
  run "$newid" XVER_DIR="$dir" XVER_ACTION=continue XVER_FROM=B XVER_TO=C XVER_ROUNDS=5 XVER_DEVICE=1
  run "$oldid" XVER_DIR="$dir" XVER_ACTION=fold XVER_FROM=C
done

if [[ $failed -ne 0 ]]; then echo "==> Builds disagree, or a run failed"; exit 1; fi
echo "==> Every fold matched"
