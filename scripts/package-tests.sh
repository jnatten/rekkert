#!/bin/bash
# The package tests, in two runs. The suites that hold the main actor for long stretches (court
# simulations that take minutes, and a two-hour evening written to the record) run on their own
# after the rest: beside them on a three-core runner, the tests that wait in real time starve.
set -euo pipefail
cd "$(dirname "$0")/.."

long='RekkertSyncTests\.(BusyHallTests|ClubNightTests|CalibrationFitTests|ClockOffsetTests|OlderHostTests|StandInDelayTests|LongEveningRecordTests)/'

swift test --package-path Packages/RekkertKit --skip "$long"

echo "==> Long court simulations, one at a time"
swift test --package-path Packages/RekkertKit --skip-build --no-parallel --filter "$long"
