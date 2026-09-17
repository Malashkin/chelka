#!/bin/bash
# Собирает Chelka.app из SPM-бинаря (LSUIElement — без иконки в доке).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Chelka.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Chelka "$APP/Contents/MacOS/Chelka"

# Иконка: лоб с чёлкой на фоне ковра (Resources/AppIcon-1024.png -> .icns)
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size*2)) $((size*2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Chelka</string>
    <key>CFBundleDisplayName</key><string>Chelka</string>
    <key>CFBundleIdentifier</key><string>dev.mike.Chelka</string>
    <key>CFBundleExecutable</key><string>Chelka</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force -s - "$APP"
echo "OK: $APP"
