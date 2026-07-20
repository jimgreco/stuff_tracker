#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_PATH="${1:-$REPO_ROOT/fastlane/review_assets/subscription-review.png}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro Max}"
DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/cubbylog-review-screenshot.XXXXXX")"

cleanup() {
  if [[ -n "${SIMULATOR_UDID:-}" ]]; then
    xcrun simctl status_bar "$SIMULATOR_UDID" clear >/dev/null 2>&1 || true
  fi
  rm -rf "$DERIVED_DATA"
}
trap cleanup EXIT

SIMULATOR_UDID="$(
  xcrun simctl list devices available --json |
    ruby -rjson -e '
      name = ARGV.fetch(0)
      devices = JSON.parse($stdin.read).fetch("devices").values.flatten
      match = devices.find { |device| device["name"] == name && device["isAvailable"] }
      abort "No available simulator named #{name}" unless match
      puts match.fetch("udid")
    ' "$SIMULATOR_NAME"
)"

mkdir -p "$(dirname "$OUTPUT_PATH")"
xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl ui "$SIMULATOR_UDID" appearance light
xcrun simctl status_bar "$SIMULATOR_UDID" override \
  --time 9:41 \
  --operatorName "" \
  --wifiBars 3 \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100

xcodebuild \
  -quiet \
  -project "$REPO_ROOT/ios/StuffTracker.xcodeproj" \
  -scheme StuffTracker \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/StuffTracker.app"
test -d "$APP_PATH"

xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
xcrun simctl launch --terminate-running-process \
  "$SIMULATOR_UDID" \
  com.jimgreco.stufftracker \
  --subscription-review-screenshot
sleep 2
xcrun simctl io "$SIMULATOR_UDID" screenshot "$OUTPUT_PATH"

echo "Captured App Review screenshot: $OUTPUT_PATH"
