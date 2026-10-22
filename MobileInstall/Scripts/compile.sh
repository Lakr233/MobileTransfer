#!/bin/zsh

set -e
set -o pipefail

cd "$(dirname $0)"

cd ../

CLEAN=0
EXPORT_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --export)
            EXPORT_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

rm -rf Build Archive Archive.* || true

export PATH=$PATH:/opt/homebrew/bin/

xcodebuild -scheme MobileInstall \
    -derivedDataPath Build \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath Archive \
    clean archive \
    CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED=NO \
    | xcbeautify

pushd Archive.xcarchive/Products/usr/local/bin/ > /dev/null
file MobileInstall

if [[ -n $EXPORT_PATH ]]; then
    DIRNAME=$(dirname "$EXPORT_PATH")
    mkdir -p "$DIRNAME" || true

    echo "[*] copying product to $EXPORT_PATH"
    cp ./MobileInstall "$EXPORT_PATH"
else
    echo "[*] product is in $(pwd)"
fi

popd > /dev/null

echo "[*] done $0"
