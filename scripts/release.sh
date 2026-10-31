#!/bin/sh
# Builds a universal BBSTool.app, signs it with Developer ID, notarizes and staples it,
# and packages it as a signed, notarized and stapled .dmg in .build/release-dmg.
#
#   VERSION=1.0.0 scripts/release.sh
#
# Needs notarization credentials stored once in the keychain:
#   xcrun notarytool store-credentials BBSTool --apple-id <Apple ID> --team-id <team ID>
#
# Environment: VERSION (required), SIGN_IDENTITY (default: the Developer ID Application
# certificate), NOTARY_PROFILE (default: BBSTool), NOTARIZE=0 to only sign.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
version=${VERSION:?set VERSION, e.g. VERSION=1.0.0}
identity=${SIGN_IDENTITY:-Developer ID Application}
profile=${NOTARY_PROFILE:-BBSTool}
app="$root/.build/app/BBSTool.app"
out="$root/.build/release-dmg"
dmg="$out/BBSTool-$version.dmg"

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --timeout 30m
}

echo "==> Building universal app $version"
VERSION=$version UNIVERSAL=1 "$root/scripts/build-app.sh"
lipo -info "$app/Contents/MacOS/BBSTool"

echo "==> Signing app with \"$identity\""
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --strict --verbose=2 "$app"

if [ "${NOTARIZE:-1}" = 1 ]; then
    echo "==> Notarizing app"
    zip=$(mktemp -d)/BBSTool.zip
    ditto -c -k --keepParent "$app" "$zip"
    notarize "$zip"
    rm -rf "$(dirname "$zip")"
    xcrun stapler staple "$app"
fi

echo "==> Creating disk image"
rm -rf "$out"
mkdir -p "$out"
staging=$(mktemp -d)
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
diskutil image create from --format UDZO --volumeName "BBSTool $version" "$staging" "$dmg" >/dev/null
rm -rf "$staging"
codesign --force --timestamp --sign "$identity" "$dmg"

if [ "${NOTARIZE:-1}" = 1 ]; then
    echo "==> Notarizing disk image"
    notarize "$dmg"
    xcrun stapler staple "$dmg"
    echo "==> Gatekeeper assessment"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
    spctl --assess --type execute --verbose=2 "$app"
fi

echo "Done: $dmg"
