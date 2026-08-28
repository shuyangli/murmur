#!/usr/bin/env bash
# Builds Murmur.app into dist/ and code-signs it.
#
# Signing matters more than usual here: macOS keys the Accessibility and Input
# Monitoring grants to the app's code signature, so an ad-hoc signature (whose
# identity changes with every build) makes the user re-grant both after each
# rebuild. A real Apple Development identity keeps the grants stable.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Murmur"
BUNDLE_ID="com.shuyangli.murmur"
DIST_DIR="dist"
APP="${DIST_DIR}/${APP_NAME}.app"

INSTALL=0
LAUNCH=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --run) LAUNCH=1 ;;
        --help|-h)
            echo "Usage: ./build.sh [--install] [--run]"
            echo "  --install  Copy the built app to /Applications"
            echo "  --run      Relaunch the app when the build finishes"
            exit 0
            ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

echo "==> Building (release)"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BIN_PATH}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
if [ -f Resources/Murmur.icns ]; then
    cp Resources/Murmur.icns "${APP}/Contents/Resources/Murmur.icns"
fi

# SwiftPM emits dependency resources as .bundle directories next to the binary.
shopt -s nullglob
for bundle in "${BIN_PATH}"/*.bundle; do
    cp -R "$bundle" "${APP}/Contents/Resources/"
done
shopt -u nullglob

printf 'APPL????' > "${APP}/Contents/PkgInfo"

echo "==> Signing"
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning \
        | awk '/Apple Development|Developer ID Application/ {print $2; exit}')"
fi
if [ -z "$IDENTITY" ]; then
    echo "    No signing identity found; falling back to ad-hoc."
    echo "    Accessibility and Input Monitoring will need re-granting after each rebuild."
    IDENTITY="-"
else
    echo "    Using identity ${IDENTITY}"
fi

# Nested code must be signed before the enclosing bundle.
find "${APP}/Contents/Resources" -maxdepth 1 -name "*.bundle" -print0 \
    | xargs -0 -I{} codesign --force --sign "$IDENTITY" --timestamp=none {} 2>/dev/null || true

codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

echo "==> Built ${APP}"

if [ "$INSTALL" -eq 1 ]; then
    echo "==> Installing to /Applications"
    osascript -e 'quit app "Murmur"' 2>/dev/null || true
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP" /Applications/
    APP="/Applications/${APP_NAME}.app"
fi

if [ "$LAUNCH" -eq 1 ]; then
    echo "==> Launching"
    osascript -e 'quit app "Murmur"' 2>/dev/null || true
    sleep 1
    open "$APP"
fi
