#!/bin/sh
# Builds BBSTool.app in .build/app from the BBSToolApp executable, signed ad hoc.
# UNIVERSAL=1 builds for both Apple silicon and Intel. scripts/release.sh signs with
# Developer ID and notarizes.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
version=${VERSION:-0.5.0}
app="$root/.build/app/BBSTool.app"

set -- --package-path "$root" -c release --product BBSToolApp
if [ "${UNIVERSAL:-0}" = 1 ]; then
    set -- "$@" --arch arm64 --arch x86_64
fi
swift build "$@"
binaries=$(swift build "$@" --show-bin-path)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binaries/BBSToolApp" "$app/Contents/MacOS/BBSTool"
cp "$root/Resources/Help.pdf" "$app/Contents/Resources/"
cp -R "$root/Resources/Profiles" "$app/Contents/Resources/"

# The original 256 px icon, scaled into an icon set
iconset=$(mktemp -d)/AppIcon.iconset
mkdir -p "$iconset"
for size in 16 32 128 256; do
    sips -z $size $size "$root/Resources/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    [ $double -le 256 ] && sips -z $double $double "$root/Resources/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$iconset")"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>BBSTool</string>
    <key>CFBundleDisplayName</key><string>BBSTool</string>
    <key>CFBundleIdentifier</key><string>io.github.nafets-asquare.BBSTool</string>
    <key>CFBundleExecutable</key><string>BBSTool</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Based on the Bafang Configuration Tool by Bafang and Stefan Penov.</string>
</dict>
</plist>
EOF

codesign --force --sign - "$app"
echo "Built $app"
