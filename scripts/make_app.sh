#!/bin/bash
# 组装 VolumeGuard.app（release 构建 + 手工 bundle + 图标 + ad-hoc 签名）
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product VolumeGuardApp

APP="build/VolumeGuard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/VolumeGuardApp "$APP/Contents/MacOS/VolumeGuard"

# 图标：无 icns 时用脚本生成
if [ ! -f build/VolumeGuard.icns ]; then
    swift scripts/make_icon.swift build/VolumeGuard.iconset
    iconutil -c icns build/VolumeGuard.iconset -o build/VolumeGuard.icns
fi
cp build/VolumeGuard.icns "$APP/Contents/Resources/VolumeGuard.icns"

# 本地化资源（英文为源语言，其余语言放 Resources/<lang>.lproj）
for lproj in Resources/*.lproj; do
    [ -e "$lproj" ] || continue
    cp -R "$lproj" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>VolumeGuard</string>
    <key>CFBundleDisplayName</key>       <string>VolumeGuard</string>
    <key>CFBundleExecutable</key>        <string>VolumeGuard</string>
    <key>CFBundleIdentifier</key>        <string>com.y5neko.volumeguard</string>
    <key>CFBundleIconFile</key>          <string>VolumeGuard</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key>           <string>2</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>CFBundleDevelopmentRegion</key> <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "打包完成: $PWD/$APP"
