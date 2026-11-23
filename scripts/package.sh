#!/bin/bash
# 打包 CheckLet：生成通用二进制（Apple 芯片 + Intel）的 .app，以及用于发布的 .dmg / .zip
#
#   ./scripts/package.sh                 # 默认 ad-hoc 签名（用户第一次打开需要在系统设置里点"仍要打开"）
#   SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" NOTARY_PROFILE=checklet ./scripts/package.sh
#                                        # 有 Apple 开发者账号时：正式签名 + 公证，用户可直接打开
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="CheckLet"
BUNDLE_ID="${BUNDLE_ID:-com.checklet.app}"
VERSION="${VERSION:-1.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
MIN_MACOS="13.0"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

DIST="dist"
APP="$DIST/$APP_NAME.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▸ 编译 arm64…"
swift build -c release --triple "arm64-apple-macosx$MIN_MACOS"
echo "▸ 编译 x86_64…"
swift build -c release --triple "x86_64-apple-macosx$MIN_MACOS"

echo "▸ 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  ".build/arm64-apple-macosx/release/$APP_NAME" \
  ".build/x86_64-apple-macosx/release/$APP_NAME" \
  -output "$APP/Contents/MacOS/$APP_NAME"

echo "▸ 生成图标"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make_icon.swift "$WORK/icon_1024.png" >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>CheckLet</string>
</dict>
</plist>
PLIST

echo "▸ 签名（$SIGN_IDENTITY）"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"

echo "▸ 制作 DMG"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "docs/安装说明.txt" "$STAGE/安装说明.txt" 2>/dev/null || true
DMG="$DIST/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

ZIP="$DIST/$APP_NAME-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ -n "${NOTARY_PROFILE:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  echo "▸ 公证（notarytool profile: $NOTARY_PROFILE）"
  codesign --force --sign "$SIGN_IDENTITY" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo ""
echo "✅ 完成"
echo "   App: $APP"
echo "   DMG: $DMG   ← 上传到 GitHub Releases"
echo "   ZIP: $ZIP"
du -sh "$APP" "$DMG" "$ZIP" | sed 's/^/   /'
