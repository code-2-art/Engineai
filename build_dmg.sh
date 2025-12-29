#!/bin/zsh

APP_PATH="build/macos/Build/Products/Release/Engineai.app"
DMG_PATH="Engineai-release.dmg"

rm -rf dmg_temp
mkdir dmg_temp
cp -R "$APP_PATH" dmg_temp/

# 创建背景目录（可选，需要背景图片）
mkdir -p dmg_temp/.background

# 创建 Applications 快捷方式
ln -s /Applications dmg_temp/Applications

hdiutil create -srcfolder dmg_temp -volname "Engineai" -fs HFS+ -format UDZO "$DMG_PATH"

rm -rf dmg_temp

echo "DMG 创建完成：$DMG_PATH"