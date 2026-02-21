#!/bin/bash
# =============================================================================
# VPS-OPS v2.0 — 证书续期脚本
# acme.sh daemon 会自动续期，本脚本在续期成功后重启 DERP 加载新证书
# 可通过 acme.sh 的 --reloadcmd 自动调用
# =============================================================================

set -euo pipefail

LOG_PREFIX="[Cert Renew]"

echo "=== ${LOG_PREFIX} 证书续期回调: $(date) ==="

# 重启 DERP 以加载新证书
echo "${LOG_PREFIX} 重启 derper 容器..."
if docker ps --format '{{.Names}}' | grep -q "^derper$"; then
    docker restart derper
    echo "${LOG_PREFIX} ✅ derper 已重启"
else
    echo "${LOG_PREFIX} ⚠️ derper 未运行"
fi

echo "=== ${LOG_PREFIX} 完成: $(date) ==="
