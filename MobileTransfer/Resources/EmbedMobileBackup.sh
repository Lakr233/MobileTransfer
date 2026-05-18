#!/bin/zsh

set -e
set -o pipefail

echo "    PROJECT_DIR: $PROJECT_DIR"
echo "    CONFIGURATION: $CONFIGURATION"
echo "    EXPANDED_CODE_SIGN_IDENTITY: $EXPANDED_CODE_SIGN_IDENTITY"
echo "    EXPANDED_CODE_SIGN_IDENTITY_NAME: $EXPANDED_CODE_SIGN_IDENTITY_NAME"
echo "    DEVELOPMENT_TEAM: $DEVELOPMENT_TEAM"

CACHE_DIR="$(pwd)/.cache"
BINARY_CACHE="$CACHE_DIR/MobileBackup"

if [ -n "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
fi
if [ ! -f ".root" ]; then
    exit 1
fi

if [ "$CONFIGURATION" = "Release" ]; then
    rm -rf $CACHE_DIR
fi
mkdir $CACHE_DIR 2> /dev/null || true 

if [ -f "$BINARY_CACHE" ]; then
    echo "Already built the binary as MobileBackup"
else
    echo "Building the binary as MobileBackup..."
    env -i /bin/zsh -c "./MobileBackup/Scripts/compile.sh --export '$BINARY_CACHE'"
fi

APP_PATH="$CODESIGNING_FOLDER_PATH"
AUX_BINARY_DIR="$APP_PATH/Contents/MacOS"
mkdir -p "$AUX_BINARY_DIR"

if [ "$CODE_SIGNING_ALLOWED" = "NO" ] || [ -z "$EXPANDED_CODE_SIGN_IDENTITY" ]; then
    echo "[*] using ad-hoc signing for CODE_SIGNING_ALLOWED=$CODE_SIGNING_ALLOWED"
    EXPANDED_CODE_SIGN_IDENTITY="-"
elif [ -n "$EXPANDED_CODE_SIGN_IDENTITY_NAME" ]; then
    echo "[*] overwrite CODE_SIGN_IDENTITY to $EXPANDED_CODE_SIGN_IDENTITY_NAME"
    CODE_SIGN_IDENTITY="$EXPANDED_CODE_SIGN_IDENTITY_NAME"
fi

MOBILE_BACKUP_TARGET="$AUX_BINARY_DIR/MobileBackup"
codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
    --entitlements "$PROJECT_DIR/MobileTransfer/Entitlements-Subprocess.entitlements" \
    -o runtime \
    "$BINARY_CACHE"

cp "$BINARY_CACHE" "$MOBILE_BACKUP_TARGET"

echo "[*] done $0"
