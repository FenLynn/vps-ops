#!/bin/bash
# =============================================================================
# VPS-OPS — 证书手动签发脚本
#
# 使用 acme daemon 容器签发 DERP 域名证书，完全绕开 acme-init 的自动化竞争
#
# 用法:
#   sudo bash cert_issue.sh              # 正式签发 (letsencrypt，每周限5次)
#   sudo bash cert_issue.sh --staging    # 测试签发 (letsencrypt_test，无限次)
#   sudo bash cert_issue.sh --force      # 强制重签 (清空旧证书数据后重签)
#   sudo bash cert_issue.sh --status     # 查看当前证书状态
# =============================================================================

set -uo pipefail

# ─── 配置区 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 加载 .env 获取 DERP_DOMAIN、CF_DNS_API_TOKEN 等
for env_file in "${PROJECT_DIR}/.env" "/opt/vps-dmz/.env"; do
    if [ -f "$env_file" ]; then
        export $(grep -v '^#' "$env_file" | grep -v '^$' | xargs) 2>/dev/null || true
        break
    fi
done

DERP_DOMAIN="${DERP_DOMAIN:-derp.660415.xyz}"
ACME_CONTAINER="${ACME_CONTAINER:-acme}"
BASE_DIR="${BASE_DIR:-/opt/vps-dmz}"
ACME_DATA_DIR="${BASE_DIR}/data/acme"
CERT_DIR="${ACME_DATA_DIR}/${DERP_DOMAIN}"
CERT_FILE="${CERT_DIR}/${DERP_DOMAIN}.crt"
KEY_FILE="${CERT_DIR}/${DERP_DOMAIN}.key"
ECC_DIR_IN_CONTAINER="/acme.sh/${DERP_DOMAIN}_ecc"

# ─── 参数解析 ─────────────────────────────────────────────────────────────────
MODE="prod"
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --staging)   MODE="staging" ;;
        --force)     FORCE=true ;;
        --status)    MODE="status" ;;
        --help|-h)
            echo "用法:"
            echo "  $0                # 正式签发 (letsencrypt，每周限5次，须先用 --staging 测试)"
            echo "  $0 --staging      # 测试签发 (letsencrypt_test，无速率限制)"
            echo "  $0 --force        # 强制重签 (清空旧证书数据后重签，配合 prod 或 staging 使用)"
            echo "  $0 --status       # 查看当前证书状态"
            echo ""
            echo "推荐流程: --staging 验证通过 → --force 清理 → 正式签发"
            exit 0
            ;;
    esac
done

# ─── ROOT 检查 ────────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 需要 root 权限运行。请使用: sudo bash $0 $*"
    exit 1
fi

echo "=============================================================="
echo "  VPS-OPS 证书签发脚本  [MODE: ${MODE^^}]"
echo "  域名: ${DERP_DOMAIN}"
echo "  容器: ${ACME_CONTAINER}"
echo "=============================================================="
echo ""

# =============================================================================
# 查询模式
# =============================================================================
if [ "$MODE" = "status" ]; then
    echo "📋 当前证书状态"
    echo ""

    # 显示容器内 acme.sh 列表
    echo "─── acme.sh 内部证书列表 ───"
    if docker ps --format '{{.Names}}' | grep -q "^${ACME_CONTAINER}$"; then
        docker exec "${ACME_CONTAINER}" acme.sh --list 2>/dev/null || echo "  (无证书记录)"
    else
        echo "  ⚠️  acme 容器未运行"
    fi

    echo ""
    echo "─── 本地证书文件 ───"
    if [ -f "$CERT_FILE" ]; then
        echo "  📁 ${CERT_FILE}"
        openssl x509 -in "$CERT_FILE" -noout -subject -dates 2>/dev/null || echo "  ❌ 证书文件损坏"
        # 检查是否为测试证书
        if openssl x509 -in "$CERT_FILE" -noout -issuer 2>/dev/null | grep -qi "fake\|test\|staging"; then
            echo "  ⚠️  这是 STAGING 测试证书！derper 需要正式证书。"
        else
            echo "  ✅ 这是正式证书"
        fi
    else
        echo "  📂 证书目录: ${CERT_DIR}"
        ls -la "${CERT_DIR}" 2>/dev/null || echo "  ❌ 目录不存在"
    fi
    exit 0
fi

# =============================================================================
# 前置检查
# =============================================================================
echo "─── 前置检查 ───────────────────────────────────────────────────"

# 1. 检查 acme daemon 是否在运行
if ! docker ps --format '{{.Names}}' | grep -q "^${ACME_CONTAINER}$"; then
    echo "❌ acme 容器未运行！请先启动:"
    echo "   cd ${BASE_DIR} && docker compose up -d acme"
    exit 1
fi
echo "  ✅ acme 容器运行中"

# 2. 检查 CF_Token
CF_TOKEN_ENV="${CF_DNS_API_TOKEN:-${CF_Token:-}}"
if [ -z "$CF_TOKEN_ENV" ]; then
    echo "❌ 未找到 CF_DNS_API_TOKEN（或 CF_Token）！"
    echo "   请检查 .env 文件中是否已配置 Cloudflare DNS API Token"
    echo "   Token 需要权限: Zone → DNS → Edit"
    exit 1
fi
echo "  ✅ CF_DNS_API_TOKEN 已配置"

# 3. 检查域名解析
echo "  - 检查 ${DERP_DOMAIN} DNS 解析..."
if ! host "${DERP_DOMAIN}" >/dev/null 2>&1; then
    echo "  ⚠️  DNS 解析检查失败（可能是 host 命令不可用，继续执行）"
else
    echo "  ✅ ${DERP_DOMAIN} DNS 解析正常"
fi

echo ""

# =============================================================================
# 强制模式: 清空旧证书数据
# =============================================================================
if [ "$FORCE" = true ]; then
    echo "⚠️  [FORCE] 清空旧证书数据（staging → prod 切换必须清理）..."

    # 备份
    if [ -d "$CERT_DIR" ]; then
        mv "$CERT_DIR" "${CERT_DIR}.bak.$(date +%s)"
        echo "  📦 已备份旧证书目录: ${CERT_DIR}.bak.*"
    fi
    # 清理 acme.sh 内部的 ECC 数据
    docker exec "${ACME_CONTAINER}" sh -c "
        rm -rf '/acme.sh/${DERP_DOMAIN}' '/acme.sh/${DERP_DOMAIN}_ecc' 2>/dev/null || true
    "
    echo "  ✅ 旧证书数据已清空"
    echo ""
fi

# =============================================================================
# 签发证书
# =============================================================================
if [ "$MODE" = "staging" ]; then
    ACME_SERVER="letsencrypt_test"
    echo "🔧 [STAGING] 使用 Let's Encrypt 测试服务器（证书不受浏览器信任）"
else
    ACME_SERVER="letsencrypt"
    echo "🔒 [PROD] 使用 Let's Encrypt 正式服务器"
fi
echo ""

# 检查是否已有有效证书（非 --force 时跳过）
if [ -s "$CERT_FILE" ] && grep -q 'BEGIN CERTIFICATE' "$CERT_FILE" 2>/dev/null; then
    echo "  ℹ️  证书已存在: ${CERT_FILE}"
    echo "  如需重签，请加 --force 参数"
    echo "  查看证书详情: $0 --status"
    exit 0
fi

# Step 1: 签发
echo "📝 Step 1: 签发证书..."
echo "   命令: acme.sh --issue --server ${ACME_SERVER} -d ${DERP_DOMAIN} --dns dns_cf --keylength ec-256"
echo "   ⏳ DNS 传播可能需要 30-120 秒，请耐心等待..."
echo ""

docker exec \
    -e "CF_Token=${CF_TOKEN_ENV}" \
    "${ACME_CONTAINER}" \
    acme.sh --issue \
        --server "${ACME_SERVER}" \
        -d "${DERP_DOMAIN}" \
        --dns dns_cf \
        --keylength ec-256

ISSUE_RC=$?
if [ $ISSUE_RC -ne 0 ]; then
    echo ""
    echo "❌ 证书签发失败 (退出码: ${ISSUE_RC})"
    echo ""
    echo "常见原因排查:"
    echo "  1. CF_DNS_API_TOKEN 权限不足  → 需要 Zone → DNS → Edit 权限"
    echo "  2. Let's Encrypt 速率限制     → 先用 --staging 测试，确认通过再正式签"
    if [ "$MODE" = "staging" ]; then
        echo "  3. DERP 域名 DNS 解析错误     → 确认 ${DERP_DOMAIN} 已在 Cloudflare 添加 A/CNAME 记录"
    else
        echo "  3. LE 速率限制 (每周5次)      → 等待或使用 --staging 先调试"
    fi
    exit 1
fi

echo ""
echo "  ✅ 证书签发成功"

# Step 2: 验证 _ecc 目录（防止 install-cert 报 Unknown parameter）
echo ""
echo "📝 Step 2: 验证 ECC 目录..."
if ! docker exec "${ACME_CONTAINER}" test -d "${ECC_DIR_IN_CONTAINER}"; then
    echo "❌ acme.sh 内部 ECC 目录不存在: ${ECC_DIR_IN_CONTAINER}"
    echo "   这是 acme.sh 的内部错误，请查看上方日志"
    exit 1
fi
echo "  ✅ ECC 目录已创建: ${ECC_DIR_IN_CONTAINER}"

# Step 3: 安装证书到 derper 期望的路径
echo ""
echo "📝 Step 3: 安装证书到 ${CERT_DIR}..."
mkdir -p "${CERT_DIR}"
docker exec "${ACME_CONTAINER}" acme.sh \
    --install-cert -d "${DERP_DOMAIN}" --ecc \
    --cert-file "/acme.sh/${DERP_DOMAIN}/${DERP_DOMAIN}.crt" \
    --key-file  "/acme.sh/${DERP_DOMAIN}/${DERP_DOMAIN}.key"

INSTALL_RC=$?
if [ $INSTALL_RC -ne 0 ]; then
    echo "❌ install-cert 失败 (退出码: ${INSTALL_RC})"
    exit 1
fi

# Step 4: 验证证书文件
echo ""
echo "📝 Step 4: 验证证书..."
if [ ! -s "$CERT_FILE" ]; then
    echo "❌ 证书文件为空或不存在: ${CERT_FILE}"
    exit 1
fi
if ! grep -q 'BEGIN CERTIFICATE' "$CERT_FILE"; then
    echo "❌ 证书文件格式错误（不含 BEGIN CERTIFICATE）"
    exit 1
fi

echo ""
echo "  📄 证书详情:"
openssl x509 -in "$CERT_FILE" -noout -subject -dates 2>/dev/null

# 检查是否为测试证书
if openssl x509 -in "$CERT_FILE" -noout -issuer 2>/dev/null | grep -qi "fake\|test\|staging"; then
    echo ""
    echo "  ⚠️  这是 STAGING 测试证书，derper 需要正式证书才能工作！"
    echo "  正式签发流程:"
    echo "    sudo bash $0 --force        # 清空测试证书"
    echo "    sudo bash $0                # 签发正式证书"
fi

echo ""
echo "=============================================================="
echo "  ✅ 证书签发完成！"
echo ""
echo "  下一步: 启动 derper 服务"
echo "    cd ${BASE_DIR} && docker compose up -d derper"
echo ""
echo "  查看证书状态:"
echo "    $0 --status"
echo "=============================================================="
