#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$SOURCE/Sources/Skytrace/Resources/catalog.sqlite" ]; then
    python3 "$SOURCE/scripts/update-catalog.py"
fi
PLATFORM="${1:-simulator}"
case "$PLATFORM" in
    simulator) SDK=iphonesimulator; DESTINATION='generic/platform=iOS Simulator'; CONFIG=Debug ;;
    device) SDK=iphoneos; DESTINATION='generic/platform=iOS'; CONFIG=Release ;;
    *) echo 'Usage: build-ios.sh [simulator|device] [derived-data-directory]' >&2; exit 2 ;;
esac
DERIVED="${2:-$SOURCE/.build-ios-$PLATFORM}"
xcodebuild -project "$SOURCE/Skytrace-iOS.xcodeproj" -scheme Skytrace-iOS \
    -sdk "$SDK" -destination "$DESTINATION" -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build
if [ "$PLATFORM" = device ]; then
    echo 'Device compilation succeeded. This build is unsigned; select a signing team in Xcode to install or distribute.'
else
    echo "Simulator app: $DERIVED/Build/Products/Debug-iphonesimulator/Skytrace.app"
fi
