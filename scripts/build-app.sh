#!/bin/bash
# Compila o pacote e monta build/Wineup Player.app com o ícone WineUp.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Wineup Player.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Wineup"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Wineup"
cp Resources/WineUp.icns "$APP/Contents/Resources/WineUp.icns"
cp Resources/THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"

# Frameworks dinâmicos (inclui os LGPL, que precisam continuar substituíveis).
mkdir -p "$APP/Contents/Frameworks"
for fw in "$(dirname "$BIN")"/*.framework; do
    [ -d "$fw" ] && cp -R "$fw" "$APP/Contents/Frameworks/"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Wineup"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Wineup Player</string>
    <key>CFBundleDisplayName</key><string>Wineup Player</string>
    <key>CFBundleExecutable</key><string>Wineup</string>
    <key>CFBundleIdentifier</key><string>app.wineup.player</string>
    <key>CFBundleIconFile</key><string>WineUp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Áudio</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>public.audio</string><string>public.folder</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

for fw in "$APP"/Contents/Frameworks/*.framework; do
    codesign --force --sign - "$fw"
done
codesign --force --sign - "$APP"
echo "Pronto: $APP"
