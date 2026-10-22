#!/bin/sh
set -eu
GO_BIN="$(command -v go || true)"
if [ -z "$GO_BIN" ] && [ -x /opt/homebrew/bin/go ]; then GO_BIN=/opt/homebrew/bin/go; fi
if [ -z "$GO_BIN" ]; then echo 'error: Go 1.25 or newer is required to build the Apple verification helper.' >&2; exit 1; fi
HELPER_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Helpers"
mkdir -p "$HELPER_DIR"
cd "$SRCROOT/Tools/AppleIDChallenge"
"$GO_BIN" build -trimpath -o "$HELPER_DIR/itm-apple-challenge" .

xcrun clang -fobjc-arc -fblocks -framework Cocoa "$SRCROOT/Tools/SystemStoreAuthentication/main.m" -o "$HELPER_DIR/itm-system-store-auth"
