#!/bin/bash

set -euo pipefail
cd "$(dirname "$0")/.."

# Load test-env.json if present (exports as env vars)
if [ -f "test-env.json" ]; then
    echo "[*] Loading credentials from test-env.json"
    while IFS='=' read -r key value; do
        export "$key=$value"
    done < <(python3 -c "
import json, sys
with open('test-env.json') as f:
    for k, v in json.load(f).items():
        if v: print(f'{k}={v}')
")
fi

COMMAND="${1:-all}"

case "$COMMAND" in
    unit)
        echo "[*] Running unit tests..."
        swift test --filter 'ApplePackageAccountTests|ApplePackageConfigurationTests|LockedStateTests|SAPAuthenticationRequestTests|SAPSyntheticTests|SAPValidationTests|SAPHandshakeTests|StoreDownloadRecoveryTests|LoginArgumentsTests'
        ;;
    network)
        echo "[*] Running network tests..."
        swift test --filter 'ApplePackageBagTests|ApplePackageLookupTests|ApplePackageSearchTests'
        ;;
    integration)
        echo "[*] Running integration tests..."
        swift test --filter 'ApplePackageAuthenticateTests|ApplePackageDownloadTests|ApplePackageVersionFinderTests|ApplePackageVersionLookupTests'
        ;;
    all)
        echo "[*] Running all tests..."
        swift test
        ;;
    *)
        echo "Usage: $0 {unit|network|integration|all}"
        exit 1
        ;;
esac
