#!/bin/bash
# Assemble the single-file Kokosuki.app bundle: binary + MLX metallib + model weights + icon.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Kokosuki.app"
BIN="$ROOT/.build/release/Kokosuki"

echo "==> swift build"
swift build -c release --package-path "$ROOT" >/dev/null

echo "==> metallib"
"$ROOT/scripts/build_metallib.sh" "$ROOT/.build/release" >/dev/null

echo "==> assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Kokosuki"
# MLX looks for a colocated mlx.metallib next to the executable
cp "$ROOT/.build/release/mlx.metallib" "$APP/Contents/MacOS/mlx.metallib"
# SwiftPM resource bundles (swift-transformers fallback configs)
for b in "$ROOT/.build/release/"*.bundle; do
  [ -d "$b" ] && cp -R "$b" "$APP/Contents/Resources/" || true
done

echo "==> model weights"
mkdir -p "$APP/Contents/Resources/model"
for f in config.json generation_config.json model.safetensors model.safetensors.index.json \
         tokenizer.json tokenizer_config.json chat_template.jinja; do
  cp "$ROOT/model/$f" "$APP/Contents/Resources/model/"
done

echo "==> icon"
ICONDIR="$ROOT/build/icon.iconset"
rm -rf "$ICONDIR"; mkdir -p "$ICONDIR"
"$BIN" --icon "$ROOT/build" >/dev/null
SRC="$ROOT/build/icon-1024.png"
for s in 16 32 64 128 256 512; do
  sips -z $s $s "$SRC" --out "$ICONDIR/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d "$SRC" --out "$ICONDIR/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONDIR" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Kokosuki</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.kokosuki.pet</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Kokosuki</string>
    <key>CFBundleDisplayName</key><string>Kokosuki</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> codesign (ad-hoc)"
codesign --force --deep -s - "$APP"

du -sh "$APP"
echo "done: $APP"
