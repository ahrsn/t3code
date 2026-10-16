#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "Install XcodeGen with: brew install xcodegen" >&2; exit 1; }
xcodegen generate
action="${1:-build}"
case "$action" in
  build|test|ui-test)
    device="${2:?Pass an existing idle iOS Simulator UDID}"
    scheme=T3Native
    operation="$action"
    if [[ "$action" == ui-test ]]; then scheme=T3NativeUI; operation=test; fi
    xcodebuild -project T3Native.xcodeproj -scheme "$scheme" \
      -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/DerivedData \
      -parallel-testing-enabled NO -jobs 2 CODE_SIGNING_ALLOWED=NO "$operation"
    ;;
  archive)
    xcodebuild -project T3Native.xcodeproj -scheme T3Native -configuration Release \
      -destination generic/platform=iOS -derivedDataPath build/DeviceData \
      -archivePath build/T3Native.xcarchive -allowProvisioningUpdates -jobs 2 archive
    ;;
  *) echo "Usage: $0 {build|test|ui-test} SIMULATOR_UDID | archive" >&2; exit 2 ;;
esac
