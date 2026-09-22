#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "🔨 正在编译 typer Release 版本..."
swift build -c release

APP_NAME="Typer"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "📦 创建应用程序结构: ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 复制二进制执行文件
cp ".build/release/ScreenTyper" "${MACOS_DIR}/Typer"
chmod +x "${MACOS_DIR}/Typer"

# 生成 App 图标
echo "🎨 生成应用图标..."
swift make_icon.swift temp_icon_1024.png
ICONSET_DIR="typer.iconset"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

sips -z 16 16     temp_icon_1024.png --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32     temp_icon_1024.png --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32     temp_icon_1024.png --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64     temp_icon_1024.png --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128   temp_icon_1024.png --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256   temp_icon_1024.png --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256   temp_icon_1024.png --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512   temp_icon_1024.png --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512   temp_icon_1024.png --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
sips -z 1024 1024 temp_icon_1024.png --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
rm -rf "${ICONSET_DIR}" temp_icon_1024.png

# 生成 Info.plist
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>Typer</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.gaoyating.typer</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Typer</string>
    <key>CFBundleDisplayName</key>
    <string>Typer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 进行 ad-hoc 签名以保证 macOS 辅助功能权限持久性
echo "🔏 为应用进行本地代码签名..."
codesign --force --deep --sign - "${APP_BUNDLE}"

# 复制到用户应用程序目录并创建桌面快捷方式
mkdir -p ~/Applications
rm -rf ~/Applications/"${APP_BUNDLE}"
cp -R "${APP_BUNDLE}" ~/Applications/
rm -f ~/Desktop/"${APP_BUNDLE}"
ln -s ~/Applications/"${APP_BUNDLE}" ~/Desktop/"${APP_BUNDLE}"

echo "📦 正在制作可分享的安装包 (DMG & ZIP)..."
ditto -c -k --keepParent "${APP_BUNDLE}" ~/Desktop/Typer.zip
hdiutil create -volname "Typer" -srcfolder "${APP_BUNDLE}" -ov -format UDZO ~/Desktop/Typer.dmg >/dev/null

echo "✅ 打包完成: ${APP_BUNDLE}"
echo "🚀 已安装至: ~/Applications/${APP_BUNDLE}"
echo "🖥️ 桌面快捷方式已就绪: ~/Desktop/${APP_BUNDLE}"
echo "🎁 分享文件已生成在桌面: ~/Desktop/Typer.dmg & ~/Desktop/Typer.zip"



