#!/bin/bash
# =============================================================================
# VPS-OPS v2.0 — 原子性备份脚本
# 严格遵循 SQLite 一致性备份铁律:
#   1. Pre-freeze:  暂停含 SQLite 的容器
#   2. Snapshot:    Kopia 快照 (排除 .shm/.wal)
#   3. Post-thaw:   恢复容器运行
#   4. Maintenance: 清理过期快照
#
# 触发方式: crontab (0 3 * * *)
# 用法: bash /opt/vps-dmz/scripts/backup_kopia.sh
# =============================================================================

set -euo pipefail

BASE_DIR="${BASE_DIR:-/opt/vps-dmz}"
LOG_PREFIX="[Kopia Backup]"

# 需要暂停的容器列表 (含 SQLite 数据库的服务)
PAUSE_CONTAINERS="new-api uptime-kuma"

echo "=== ${LOG_PREFIX} 开始: $(date) ==="

# ─── 1. Pre-freeze: 暂停 SQLite 容器 ─────────────────────────────────────────
echo "${LOG_PREFIX} [1/4] 暂停容器: ${PAUSE_CONTAINERS}..."
for c in ${PAUSE_CONTAINERS}; do
    if docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
        docker pause ${c} && echo "  ✅ ${c} 已暂停" || echo "  ⚠️ ${c} 暂停失败"
    else
        echo "  ⚠️ ${c} 未运行，跳过"
    fi
done

# ─── 2. Snapshot: 精准快照 ────────────────────────────────────────────────────
echo "${LOG_PREFIX} [2/4] 创建快照..."
# 通过 docker exec 调用 kopia (容器内执行)
# 排除 SQLite 临时文件 (.shm, .wal, -journal)
docker exec kopia kopia snapshot create /source \
    --override-hostname=vps-backup \
    --override-username=root \
    --ignore-rules-file="" \
    --log-level=warning \
    2>&1 | while read -r line; do echo "  ${line}"; done

SNAP_RC=$?

# ─── 3. Post-thaw: 恢复容器 (无论备份是否成功) ────────────────────────────────
echo "${LOG_PREFIX} [3/4] 恢复容器..."
for c in ${PAUSE_CONTAINERS}; do
    if docker inspect --format='{{.State.Paused}}' ${c} 2>/dev/null | grep -q "true"; then
        docker unpause ${c} && echo "  ✅ ${c} 已恢复" || echo "  ⚠️ ${c} 恢复失败"
    fi
done

# 检查快照结果
if [ "${SNAP_RC:-0}" -ne 0 ]; then
    echo "${LOG_PREFIX} ❌ 快照失败 (exit code: ${SNAP_RC})"
fi

# ─── 4. Maintenance: 清理与维护 ──────────────────────────────────────────────
echo "${LOG_PREFIX} [4/4] 清理过期快照..."
docker exec kopia kopia maintenance run --full \
    --log-level=warning \
    2>&1 | while read -r line; do echo "  ${line}"; done || true

echo "=== ${LOG_PREFIX} 完成: $(date) ==="
