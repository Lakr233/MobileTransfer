#!/bin/zsh

set -e
set -o pipefail

cd "$(dirname "$0")"
WORKSPACE=$(pwd)

CLEAN=0
while [[ $# -gt 0 ]]; do
    case $1 in
    --clean)
        CLEAN=1
        shift
        ;;
    *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

if [[ $CLEAN -eq 1 ]]; then
    git clean -fdx -f
    git reset --hard
fi

echo "[*] start $0 at $(date)"

rm -rf $WORKSPACE/iTM.app 2>/dev/null || true

echo "[*] resolve dependencies..."
xcodebuild -resolvePackageDependencies \
    -workspace MobileTransfer.xcworkspace \
    -scheme MobileTransfer \
    | xcbeautify

echo "[*] building..."
xcodebuild -scheme MobileTransfer \
    -workspace MobileTransfer.xcworkspace \
    -derivedDataPath Build \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath Archive \
    clean archive \
    | xcbeautify

echo "[*] exporting..."
xcodebuild \
    -archivePath Archive.xcarchive \
    -exportOptionsPlist MobileTransfer/Resources/ExportOptions.plist \
    -exportPath Build/iTM \
    -allowProvisioningUpdates \
    -exportArchive \
    | xcbeautify

echo "[*] searching for app..."
APP_PATH=$(realpath Build/iTM/*.app)

echo "[*] product at $APP_PATH"

echo "[*] notarizing..."
ITM_NOTARY_PROFILE=${ITM_NOTARY_PROFILE:?Set ITM_NOTARY_PROFILE to your notarytool keychain profile}
/usr/bin/ditto -c -k --keepParent \
    "$APP_PATH" \
    "Build/iTM.zip"

xcrun notarytool submit \
    --keychain-profile "$ITM_NOTARY_PROFILE" \
    --wait \
    "Build/iTM.zip"

rm -rf "Build/iTM.zip"

echo "[*] stapling ticket..."
xcrun stapler staple $APP_PATH
spctl -a -v $APP_PATH

echo "[*] copying..."
cp -a $APP_PATH $WORKSPACE/iTM.app

echo "[*] done $0 at $(date)"
