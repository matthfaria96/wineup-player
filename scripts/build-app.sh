#!/bin/bash
# Compila o pacote e monta build/Wineup Player.app com o ícone WineUp.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Wineup Player.app"

if [ "${SKIP_TESTS:-0}" != "1" ]; then
    echo "Rodando testes do núcleo..."
    ./scripts/test.sh
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Wineup"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Wineup"
cp Resources/WineUp.icns "$APP/Contents/Resources/WineUp.icns"
./scripts/notices-versions.sh
cp Resources/THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
# Clipes embutidos do painel visual (domínio público / CC, ver THIRD_PARTY_NOTICES.md).
cp -R Resources/Videos "$APP/Contents/Resources/Videos"
# Skins embutidos (arte, fontes OFL e skin.json).
cp -R Resources/Skins "$APP/Contents/Resources/Skins"
# Traduções (Localization/*.json): menus e janelas do sistema também seguem o idioma escolhido.
python3 scripts/l10n.py build "$APP/Contents/Resources"

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
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>pt-BR</string><string>es</string><string>de</string><string>fr</string><string>it</string><string>ru</string><string>uk</string><string>pl</string><string>cs</string><string>hu</string><string>nl</string><string>sv</string><string>tr</string><string>ja</string><string>ko</string><string>zh-Hans</string></array>
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
            <array><string>public.audio</string><string>public.folder</string><string>public.m3u-playlist</string><string>public.mpeg-4-playlist</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>Skin do Wineup</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>CFBundleTypeIconFile</key><string>WineUp</string>
            <key>LSItemContentTypes</key><array><string>app.wineup.skin</string></array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>app.wineup.skin</string>
            <key>UTTypeDescription</key><string>Skin do Wineup</string>
            <key>UTTypeConformsTo</key><array><string>public.zip-archive</string><string>public.data</string></array>
            <key>UTTypeIconFile</key><string>WineUp</string>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>wineupskin</string></array></dict>
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

./scripts/verify-app.sh "$APP"
if [ "${SKIP_SMOKE:-0}" != "1" ]; then
    ./scripts/smoke-playback.sh "$APP"
fi
