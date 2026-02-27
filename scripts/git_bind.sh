#!/bin/bash
# =============================================================================
# git_bind.sh — 手动将 VPS 部署目录绑定到 GitHub 私有仓库
# =============================================================================
# 使用场景：bootstrap/deploy 采用 ssh_push 模式时，Git 绑定被跳过。
#          需要启用 git pull 更新时，在 VPS 上手动执行此脚本一次即可。
#
# 使用方法：
#   cd /opt/vps-dmz
#   bash scripts/git_bind.sh
#
# 前提：
#   - /opt/vps-dmz/.env 中包含 GH_TOKEN（具有 repo 权限的 PAT）
#   - /opt/vps-dmz/.env 中包含 GITHUB_REPO（格式：owner/repo-name）
# =============================================================================

set -e

DEPLOY_DIR="/opt/vps-dmz"
ENV_FILE="$DEPLOY_DIR/.env"

# ── 读取 .env ──────────────────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 错误: 未找到 $ENV_FILE，请先完成部署初始化。"
  exit 1
fi

# 仅加载需要的两个变量，安全过滤
GH_TOKEN=$(grep -E '^GH_TOKEN=' "$ENV_FILE" | head -1 | cut -d '=' -f2- | tr -d '[:space:]')
GITHUB_REPO=$(grep -E '^GITHUB_REPO=' "$ENV_FILE" | head -1 | cut -d '=' -f2- | tr -d '[:space:]')

if [ -z "$GH_TOKEN" ]; then
  echo "❌ 错误: .env 中未找到 GH_TOKEN，无法访问私有仓库。"
  echo "   请在 .env 中添加一行: GH_TOKEN=ghp_xxxxx（需要 repo 权限）"
  exit 1
fi

if [ -z "$GITHUB_REPO" ]; then
  echo "❌ 错误: .env 中未找到 GITHUB_REPO（格式：owner/repo-name）。"
  echo "   请在 .env 中添加一行: GITHUB_REPO=FenLynn/vps-ops"
  exit 1
fi

TARGET_URL="https://${GH_TOKEN}@github.com/${GITHUB_REPO}.git"
SAFE_URL="https://***@github.com/${GITHUB_REPO}.git"  # 用于日志输出，隐藏 token

echo "📁 部署目录: $DEPLOY_DIR"
echo "🔗 目标仓库: $SAFE_URL"
echo ""

# ── 安装 git（如未安装）────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
  echo "📦 正在安装 git..."
  apt-get install -y -qq git 2>/dev/null || yum install -y git 2>/dev/null
fi

# ── 绑定 Git 仓库 ──────────────────────────────────────────────────────────
cd "$DEPLOY_DIR"

git config --global --add safe.directory "$DEPLOY_DIR"

# 关闭所有交互式认证提示，失败立刻报错而非卡住
export GIT_TERMINAL_PROMPT=0

if [ ! -d .git ]; then
  echo "🚀 初始化 Git 仓库并绑定远端..."
  git init -b main
  git remote add origin "$TARGET_URL"
else
  echo "🔄 更新远端 URL..."
  git remote set-url origin "$TARGET_URL"
fi

echo "⬇️  正在 fetch 远端 main 分支..."
git fetch origin main

# --mixed: HEAD 指向 origin/main，暂存区同步，工作区文件保持不变
git reset --mixed origin/main

# ✅ 【新增】设置本地 main 分支跟踪远程 origin/main 分支，解决直接 git pull 报错的问题
git branch --set-upstream-to=origin/main main

echo ""
echo "✅ Git 仓库绑定完成！"
echo "   后续可直接在 $DEPLOY_DIR 执行: git pull"
