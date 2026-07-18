#!/bin/bash
#
# build_ipa.sh — 构建 TrollStore 可安装的 NotificationForwarder.ipa
#
# 用途：
#   在 macOS 上用 Xcode 构建主 App + Notification Service Extension，
#   拆出 .app 包，用 ldid 注入假签名 + 应用 entitlements，
#   打包成 TrollStore 可识别的 IPA。
#
# 前置条件（macOS）：
#   1. Xcode 14+ 已安装
#   2. ldid 已安装：brew install ldid
#   3. 任意 Apple ID 已加入 Xcode → Settings → Accounts
#      （免费 Apple ID 也可，本脚本会用 CODE_SIGN_IDENTITY="" 跳过 Xcode 签名）
#
# 用法：
#   chmod +x build_ipa.sh
#   ./build_ipa.sh                  # 用默认 bundle id
#   ./build_ipa.sh com.you.nf       # 自定义主 App bundle id
#
# 输出：
#   build/NotificationForwarder.ipa
#
set -euo pipefail

# ---------- 配置 ----------
# 项目根目录 = 仓库根（含 project.yml 的目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 兜底：如果当前推算出的 PROJECT_DIR 没有 project.yml，往上找
if [ ! -f "$PROJECT_DIR/project.yml" ]; then
    CUR="$SCRIPT_DIR"
    while [ "$CUR" != "/" ]; do
        if [ -f "$CUR/project.yml" ]; then
            PROJECT_DIR="$CUR"
            break
        fi
        CUR="$(dirname "$CUR")"
    done
fi
[ -f "$PROJECT_DIR/project.yml" ] || { echo "❌ 找不到 project.yml（从 $SCRIPT_DIR 起向上查找）"; exit 1; }

WORK_DIR="$PROJECT_DIR/build_output"
DERIVED_DATA="$WORK_DIR/DerivedData"
IPA_OUT="$WORK_DIR/NotificationForwarder.ipa"

# Bundle ID（可由参数覆盖）
MAIN_BUNDLE_ID="${1:-com.notificationforwarder.app}"
EXT_BUNDLE_ID="$MAIN_BUNDLE_ID.service"

# TrollStore 兼容：使用空 team id
DEVELOPMENT_TEAM=""

# 工具检查
command -v xcodebuild >/dev/null || { echo "❌ 需要 Xcode（xcodebuild）"; exit 1; }
command -v ldid >/dev/null        || { echo "❌ 需要安装 ldid：brew install ldid"; exit 1; }
command -v zip >/dev/null         || { echo "❌ 需要 zip 命令"; exit 1; }

cd "$PROJECT_DIR"
echo "📁 项目目录: $PROJECT_DIR"
echo "🏷  Bundle ID: $MAIN_BUNDLE_ID (ext: $EXT_BUNDLE_ID)"
echo "📂 工作目录: $WORK_DIR"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# ---------- 0. 用 xcodegen 生成 Xcode 工程（如未生成） ----------
# project.yml 位于仓库根目录
if [ ! -d "$PROJECT_DIR/NotificationForwarder.xcodeproj" ]; then
    echo ""
    echo "⚙️  [0/5] 用 xcodegen 生成 Xcode 工程..."
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "   安装 xcodegen: brew install xcodegen"
        brew install xcodegen || { echo "❌ xcodegen 安装失败"; exit 1; }
    fi
    (cd "$PROJECT_DIR" && xcodegen generate) || { echo "❌ xcodegen 失败"; exit 1; }
fi

# ---------- 1. xcodebuild archive（不签名，只编译） ----------
echo ""
echo "🔨 [1/5] 编译工程（不签名）..."

# 找 .xcodeproj / .xcworkspace
PROJECT_PATH=""
for cand in \
    "$PROJECT_DIR/NotificationForwarder.xcodeproj" \
    "$PROJECT_DIR/NotificationForwarder.xcworkspace"; do
    if [ -e "$cand" ]; then
        PROJECT_PATH="$cand"
        break
    fi
done
[ -n "$PROJECT_PATH" ] || { echo "❌ 找不到 .xcodeproj / .xcworkspace"; exit 1; }

if [[ "$PROJECT_PATH" == *.xcworkspace ]]; then
    PROJECT_ARG="-workspace $PROJECT_PATH"
else
    PROJECT_ARG="-project $PROJECT_PATH"
fi
echo "   工程: $PROJECT_PATH"

# 通用 scheme 名
SCHEME="${SCHEME:-NotificationForwarder}"

xcodebuild archive \
    $PROJECT_ARG \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$WORK_DIR/NotificationForwarder.xcarchive" \
    -destination "generic/platform=ios" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    PRODUCT_BUNDLE_IDENTIFIER="$MAIN_BUNDLE_ID" \
    AD_HOC_CODE_SIGNING_ALLOWED=YES \
    | tee "$WORK_DIR/build.log" || {
        echo "❌ 编译失败，请查看 $WORK_DIR/build.log"
        exit 1
    }

# ---------- 2. 从 .xcarchive 提取 .app ----------
echo ""
echo "📦 [2/5] 提取 .app..."
APP_PATH="$WORK_DIR/NotificationForwarder.xcarchive/Products/Applications/NotificationForwarder.app"
if [ ! -d "$APP_PATH" ]; then
    # 找到 Applications 下第一个 .app
    APP_PATH=$(find "$WORK_DIR/NotificationForwarder.xcarchive/Products/Applications" -maxdepth 1 -name "*.app" | head -1)
fi
[ -d "$APP_PATH" ] || { echo "❌ 未在 xcarchive 中找到 .app"; exit 1; }
echo "   App: $APP_PATH"

# 复制到干净目录
STAGE_DIR="$WORK_DIR/Payload"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"

APP_NAME=$(basename "$APP_PATH")           # 形如 NotificationForwarder.app
EXEC_NAME="${APP_NAME%.app}"               # 形如 NotificationForwarder（可执行文件名）
STAGED_APP="$STAGE_DIR/$APP_NAME"

# ---------- 3. ldid 注入假签名 + entitlements ----------
echo ""
echo "✍️  [3/5] 用 ldid 注入 entitlements（TrollStore 假签名）..."

PLIST_BUDDY=/usr/libexec/PlistBuddy
ENT_MAIN="$PROJECT_DIR/NotificationForwarder/NotificationForwarder.entitlements"
ENT_EXT="$PROJECT_DIR/NotificationForwarder/NotificationServiceExtension.entitlements"

# 主 App：签名可执行文件
$PLIST_BUDDY -c "Set :CFBundleIdentifier $MAIN_BUNDLE_ID" "$STAGED_APP/Info.plist" 2>/dev/null || true
$PLIST_BUDDY -c "Set :CFBundleExecutable $EXEC_NAME" "$STAGED_APP/Info.plist" 2>/dev/null || true
MAIN_EXEC="$STAGED_APP/$EXEC_NAME"
echo "   签名主 App 可执行文件: $MAIN_EXEC"
ldid -S"$ENT_MAIN" "$MAIN_EXEC"
echo "   ✓ 主 App 已签名"

# Extension：签名 .appex 内的可执行文件
EXT_APP_PATH="$STAGED_APP/PlugIns/NotificationServiceExtension.appex"
if [ ! -d "$EXT_APP_PATH" ]; then
    EXT_APP_PATH=$(find "$STAGED_APP/PlugIns" -maxdepth 1 -name "*.appex" | head -1)
fi
if [ -d "$EXT_APP_PATH" ]; then
    EXT_DIR_NAME=$(basename "$EXT_APP_PATH")        # NotificationServiceExtension.appex
    EXT_EXEC_NAME="${EXT_DIR_NAME%.appex}"           # NotificationServiceExtension
    EXT_EXEC="$EXT_APP_PATH/$EXT_EXEC_NAME"
    $PLIST_BUDDY -c "Set :CFBundleIdentifier $EXT_BUNDLE_ID" "$EXT_APP_PATH/Info.plist" 2>/dev/null || true
    $PLIST_BUDDY -c "Set :CFBundleExecutable $EXT_EXEC_NAME" "$EXT_APP_PATH/Info.plist" 2>/dev/null || true
    echo "   签名 Extension 可执行文件: $EXT_EXEC"
    ldid -S"$ENT_EXT" "$EXT_EXEC"
    echo "   ✓ Extension 已签名"
else
    echo "   ⚠️  未找到 Extension .appex，跳过"
fi

# ---------- 4. 打包成 IPA ----------
echo ""
echo "🗜  [4/5] 打包 IPA..."
cd "$WORK_DIR"
rm -f "$IPA_OUT"
zip -qr "$IPA_OUT" Payload/
echo "   ✓ $IPA_OUT"

# ---------- 5. 完成 ----------
echo ""
echo "✅ [5/5] 完成！"
echo ""
echo "IPA 路径: $IPA_OUT"
echo ""
echo "📲 安装方法："
echo "   1. 把 IPA 传到 iPhone（AirDrop / Safari 下载 / 文件 App）"
echo "   2. 在 TrollStore 中点 'Install IPA' 选择此文件"
echo "   3. 安装完成后到 设置 → 通用 → VPN与设备管理 信任（如有提示）"
echo "   4. 启动 App，在 '目标' 页配置转发目标"
echo "   5. 在 '设置 → 本地模拟推送' 中点击测试"
echo ""
echo "⚠️  TrollStore 安装的 App 可能收不到真实 APNs，"
echo "   但 '本地模拟推送' 入口可以完整验证转发链路（直接走 Dispatcher 代码路径）。"
echo ""
