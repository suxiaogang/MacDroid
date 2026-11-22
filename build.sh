#!/bin/bash
#
# MacDroid 构建脚本 (无需完整 Xcode, 依赖 Xcode Command Line Tools)
# 产出要求:
#   - Universal 二进制 (arm64 + x86_64), 同时支持 Apple Silicon 和 Intel
#   - 最低系统 macOS 14.0 (与 Info.plist / README 声明一致)
#   - ad-hoc 签名
#
set -euo pipefail

cd "$(dirname "$0")"

DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
APP_NAME="MacDroid.app"
SDK="$(xcrun --show-sdk-path)"

echo "==> 清理旧产物..."
rm -rf build "$APP_NAME"
mkdir -p build "$APP_NAME/Contents/MacOS" "$APP_NAME/Contents/Resources"

compile() {
  # compile <输出路径> <swift target 三元组>
  swiftc -parse-as-library src/main.swift \
    -o "$1" \
    -target "$2" \
    -framework SwiftUI \
    -framework AppKit \
    -sdk "$SDK"
}

echo "==> 编译二进制 (universal, macOS ${DEPLOYMENT_TARGET}+)..."
compile build/MacDroid-arm64  "arm64-apple-macosx${DEPLOYMENT_TARGET}"
compile build/MacDroid-x86_64 "x86_64-apple-macosx${DEPLOYMENT_TARGET}"
lipo -create \
  build/MacDroid-arm64 \
  build/MacDroid-x86_64 \
  -output "$APP_NAME/Contents/MacOS/MacDroid"

echo "==> 打包应用..."
cp Resources/Info.plist "$APP_NAME/Contents/Info.plist"
if [ ! -f icon.icns ]; then
  echo "错误: 缺少根目录图标文件 icon.icns" >&2
  exit 1
fi
cp icon.icns "$APP_NAME/Contents/Resources/AppIcon.icns"

echo "==> 打包本地化资源..."
# 仅依赖 CLT：直接复制 .lproj 目录（无需 actool/genstrings）
LANGS=()
for lproj in Resources/*.lproj; do
  [ -d "$lproj" ] || continue
  name="$(basename "$lproj" .lproj)"
  if [ ! -f "$lproj/Localizable.strings" ]; then
    echo "错误: $lproj 缺少 Localizable.strings" >&2
    exit 1
  fi
  cp -R "$lproj" "$APP_NAME/Contents/Resources/"
  LANGS+=("$name")
  echo "    $name"
done
if [ ${#LANGS[@]} -eq 0 ]; then
  echo "错误: 未找到任何 .lproj 本地化目录" >&2
  exit 1
fi
# 把支持的语言写入 Info.plist（CFBundleLocalizations）
/usr/libexec/PlistBuddy -c "Delete :CFBundleLocalizations" "$APP_NAME/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations array" "$APP_NAME/Contents/Info.plist" >/dev/null
for lang in "${LANGS[@]}"; do
  /usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations: string $lang" "$APP_NAME/Contents/Info.plist" >/dev/null
done
plutil -lint "$APP_NAME/Contents/Info.plist"

echo "==> 清洗扩展属性..."
xattr -cr "$APP_NAME"
find "$APP_NAME" \( -name .DS_Store -o -name '._*' \) -delete

echo "==> ad-hoc 签名..."
codesign --force --sign - "$APP_NAME"

rm -rf build

echo "==> 构建完成"
echo "应用路径: $(pwd)/$APP_NAME"
lipo -info "$APP_NAME/Contents/MacOS/MacDroid"
codesign --verify --deep --strict "$APP_NAME"