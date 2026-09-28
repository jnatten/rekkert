#!/bin/bash
# What to Test for a TestFlight build: the subject of every commit after <since>, under New,
# Fixed or Other by its conventional-commit type, and the commit it was built from last.
#
#   scripts/test-notes.sh 7801cb9   # what a build of HEAD brings over one of 7801cb9
#
# .github/workflows/testflight.yml passes the commit of its last successful run, and
# `swift scripts/build-number.swift notes` puts the result on the build.
set -euo pipefail
cd "$(dirname "$0")/.."

since=${1:?usage: scripts/test-notes.sh <commit>}
ref=${GITHUB_REF_NAME:-$(git branch --show-current)}

git log --no-merges --format=%s "$since..HEAD" |
  awk -v head="$(git rev-parse --short HEAD)" -v ref="$ref" '
  {
    type = ""
    text = $0
    if (match(text, /^[a-z]+(\([^)]*\))?!?: /)) {
      type = substr(text, 1, RLENGTH)
      sub(/[(!:].*/, "", type)
      text = substr(text, RLENGTH + 1)
    }
    # macOS awk cuts strings by the byte, so "å" in half would stop it cold.
    if (text ~ /^[a-z]/) text = toupper(substr(text, 1, 1)) substr(text, 2)
    line = "• " text "\n"
    if (type == "feat") new = new line
    else if (type == "fix") fixed = fixed line
    else other = other line
  }
  END {
    if (NR == 0) print "Nothing new since the build before.\n"
    if (new != "") printf "New\n%s\n", new
    if (fixed != "") printf "Fixed\n%s\n", fixed
    if (other != "") printf "Other\n%s\n", other
    print head (ref != "" ? " on " ref : "")
  }'
