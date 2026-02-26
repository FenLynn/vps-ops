#!/bin/bash
# =============================================================================
# VPS-OPS v2.0 — 证书续期脚本
# acme.sh daemon 会自动续期，本脚本在续期成功后重启 DERP 加载新证书
# 可通过 acme.sh 的 --reloadcmd 自动调用
# =============================================================================

set -euo pipefail

LOG_PREFIX="[Cert Renew]"

# ─── 加载 .env 以获取 PUSHPLUS_TOKEN ─────────────────────────────────────────
BASE_DIR="${BASE_DIR:-/opt/vps-dmz}"
if [ -f "${BASE_DIR}/.env" ]; then
    export $(grep -v '^#' "${BASE_DIR}/.env" | xargs) 2>/dev/null || true
fi

send_pushplus() {
    local title="$1"
    local content="$2"
    if [ -n "${PUSHPLUS_TOKEN:-}" ]; then
        curl -s -X POST "http://www.pushplus.plus/send" \
            -H "Content-Type: application/json" \
            -d "{\"token\":\"${PUSHPLUS_TOKEN}\",\"title\":\"${title}\",\"content\":\"${content}\",\"template\":\"markdown\"}" > /dev/null
    fi
}

echo "=== ${LOG_PREFIX} 证书续期回调: $(date) ==="

# 重启 DERP 以加载新证书
echo "${LOG_PREFIX} 重启 derper 容器..."
if docker ps --format '{{.Names}}' | grep -q "^derper$"; then
    if docker restart derper; then
        echo "${LOG_PREFIX} ✅ derper 已重启，新证书已加载"
        send_pushplus "[VPS] DERP 证书续期成功" "acme.sh 已成功续期 SSL 证书并重启了 DERP 中继节点。<br/>Tailscale 连接正常，证书又延了 90 天！<br/>时间: $(date)"
    else
        echo "${LOG_PREFIX} ❌ derper 重启失败！"
        send_pushplus "[VPS-告警] DERP 证书续期后容器重启失败！" "acme.sh 续期成功，但 \`docker restart derper\` 失败了！<br/>DERP 中继节点可能使用旧证书或已离线，请立即检查！<br/>时间: $(date)"
        exit 1
    fi
else
    echo "${LOG_PREFIX} ⚠️ derper 未运行"
    send_pushplus "[VPS-告警] DERP 证书续期时容器未运行" "acme.sh 触发续期回调，但发现 derper 容器并未在运行！<br/>请立即检查 \`docker ps\` 状态。<br/>时间: $(date)"
fi

echo "=== ${LOG_PREFIX} 完成: $(date) ==="
