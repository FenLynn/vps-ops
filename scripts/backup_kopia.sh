#!/bin/bash
# =============================================================================
# VPS-OPS v2.0 — 原子性备份脚本
# 严格遵循 SQLite 一致性备份铁律:
#   1. Pre-freeze:  暂停含 SQLite 的容器
#   2. Snapshot:    Kopia 快照 (增量推送到 Cloudflare R2)
#   3. Post-thaw:   恢复容器运行
#   4. Maintenance: 清理过期快照
#
# 触发方式: crontab (0 3 * * *)
# 用法: bash /opt/vps-dmz/scripts/backup_kopia.sh
# =============================================================================

set -uo pipefail
# 注意: 不使用 set -e，因为我们需要手动控制错误处理以确保 unpause 总是执行

BASE_DIR="${BASE_DIR:-/opt/vps-dmz}"
LOG_PREFIX="[Kopia Backup]"

# ⚠️ 必须暂停的容器：所有包含 SQLite 数据库的服务
# uptime-kuma: kuma.db
# memos:       memos_prod.db
# alist:       data.db + config.json
PAUSE_CONTAINERS="uptime-kuma memos alist"

# Uptime Kuma 被动心跳监控 URL（Heartbeat）
# 在 Uptime Kuma -> 添加监控 -> 类型选"Push"-> 复制 URL 填到此处
# 留空则不上报
UPTIME_KUMA_HEARTBEAT_URL="${UPTIME_KUMA_BACKUP_HEARTBEAT:-}"

# ─── 消息推送助手 ────────────────────────────────────────────────────────────
send_pushplus() {
    local title="$1"
    local content="$2"
    if [ -n "${PUSHPLUS_TOKEN:-}" ]; then
        curl -s -X POST "http://www.pushplus.plus/send" \
            -H "Content-Type: application/json" \
            -d "{\"token\":\"${PUSHPLUS_TOKEN}\",\"title\":\"${title}\",\"content\":\"${content}\",\"template\":\"markdown\"}" > /dev/null
    fi
}

# ─── 安全网: 确保容器在任何情况下都会恢复 ─────────────────────────────────────
cleanup() {
    echo "${LOG_PREFIX} [安全网] 确保所有容器已恢复..."
    for c in ${PAUSE_CONTAINERS}; do
        if docker inspect --format='{{.State.Paused}}' ${c} 2>/dev/null | grep -q "true"; then
            docker unpause ${c} && echo "  ✅ ${c} 已恢复" || echo "  ⚠️ ${c} 恢复失败"
        fi
    done
}
trap cleanup EXIT

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

# ─── 2. Snapshot: 精准快照 (直连 Cloudflare R2) ──────────────────────────────
echo "${LOG_PREFIX} [2/4] 创建快照..."

SNAP_SUCCESS=false

# R2 对象存储无并发限制，全速打快照
SNAP_OUTPUT=$(docker exec kopia kopia snapshot create /source \
    --log-level=warning \
    2>&1)
SNAP_RC=$?

echo "${SNAP_OUTPUT}" | while read -r line; do echo "  ${line}"; done

if [ ${SNAP_RC} -eq 0 ]; then
    SNAP_SUCCESS=true
    echo "  ✅ 快照创建成功"
else
    echo "  ❌ 快照失败 (exit code: ${SNAP_RC})"
fi

# ─── 3. Post-thaw: 恢复容器 (由 trap 保障，此处显式执行) ─────────────────────
echo "${LOG_PREFIX} [3/4] 恢复容器..."
for c in ${PAUSE_CONTAINERS}; do
    if docker inspect --format='{{.State.Paused}}' ${c} 2>/dev/null | grep -q "true"; then
        docker unpause ${c} && echo "  ✅ ${c} 已恢复" || echo "  ⚠️ ${c} 恢复失败"
    fi
done

# ─── 4. Maintenance: 清理与维护 ──────────────────────────────────────────────
if [ "${SNAP_SUCCESS}" = true ]; then
    echo "${LOG_PREFIX} [4/4] 清理过期快照..."
    docker exec kopia kopia maintenance run \
        --log-level=warning \
        2>&1 | while read -r line; do echo "  ${line}"; done || true
else
    echo "${LOG_PREFIX} [4/4] ⚠️ 快照失败，跳过维护清理"
fi

# ─── 完成 ────────────────────────────────────────────────────────────────────
if [ "${SNAP_SUCCESS}" = true ]; then
    echo "=== ${LOG_PREFIX} ✅ 完成: $(date) ==="
    # Uptime Kuma 被动心跳上报（告知备份按时完成）
    if [ -n "${UPTIME_KUMA_HEARTBEAT_URL}" ]; then
        curl -s "${UPTIME_KUMA_HEARTBEAT_URL}" > /dev/null && \
            echo "  ✅ Uptime Kuma 心跳已上报"
    fi
else
    echo "=== ${LOG_PREFIX} ❌ 失败: $(date) ==="
    send_pushplus "[VPS-告警] 灾备快照失败" "您的服务器在尝试执行全量容器快照倒排备份时遇到致命错误，错误代码 ${SNAP_RC}。<br/>请立即登录服务器，使用 \`docker logs kopia\` 检查！<br/>时间: $(date)"
    exit 1
fi


set -uo pipefail
# 注意: 不使用 set -e，因为我们需要手动控制错误处理以确保 unpause 总是执行

BASE_DIR="${BASE_DIR:-/opt/vps-dmz}"
LOG_PREFIX="[Kopia Backup]"

# 需要暂停的容器列表 (含 SQLite 数据库的服务)
PAUSE_CONTAINERS="uptime-kuma"

# ─── 消息推送助手 ────────────────────────────────────────────────────────────
send_pushplus() {
    local title="$1"
    local content="$2"
    if [ -n "${PUSHPLUS_TOKEN:-}" ]; then
        curl -s -X POST "http://www.pushplus.plus/send" \
            -H "Content-Type: application/json" \
            -d "{\"token\":\"${PUSHPLUS_TOKEN}\",\"title\":\"${title}\",\"content\":\"${content}\",\"template\":\"markdown\"}" > /dev/null
    fi
}

# ─── 安全网: 确保容器在任何情况下都会恢复 ─────────────────────────────────────
cleanup() {
    echo "${LOG_PREFIX} [安全网] 确保所有容器已恢复..."
    for c in ${PAUSE_CONTAINERS}; do
        if docker inspect --format='{{.State.Paused}}' ${c} 2>/dev/null | grep -q "true"; then
            docker unpause ${c} && echo "  ✅ ${c} 已恢复" || echo "  ⚠️ ${c} 恢复失败"
        fi
    done
}
trap cleanup EXIT

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

# ─── 2. Snapshot: 精准快照 (直连 Cloudflare R2) ──────────────────────────────
echo "${LOG_PREFIX} [2/4] 创建快照..."

SNAP_SUCCESS=false

# R2 对象存储无并发限制，全速打快照
SNAP_OUTPUT=$(docker exec kopia kopia snapshot create /source \
    --log-level=warning \
    2>&1)
SNAP_RC=$?

echo "${SNAP_OUTPUT}" | while read -r line; do echo "  ${line}"; done

if [ ${SNAP_RC} -eq 0 ]; then
    SNAP_SUCCESS=true
    echo "  ✅ 快照创建成功"
else
    echo "  ❌ 快照失败 (exit code: ${SNAP_RC})"
fi

# ─── 3. Post-thaw: 恢复容器 (由 trap 保障，此处显式执行) ─────────────────────
echo "${LOG_PREFIX} [3/4] 恢复容器..."
for c in ${PAUSE_CONTAINERS}; do
    if docker inspect --format='{{.State.Paused}}' ${c} 2>/dev/null | grep -q "true"; then
        docker unpause ${c} && echo "  ✅ ${c} 已恢复" || echo "  ⚠️ ${c} 恢复失败"
    fi
done

# ─── 4. Maintenance: 清理与维护 ──────────────────────────────────────────────
if [ "${SNAP_SUCCESS}" = true ]; then
    echo "${LOG_PREFIX} [4/4] 清理过期快照..."
    docker exec kopia kopia maintenance run \
        --log-level=warning \
        2>&1 | while read -r line; do echo "  ${line}"; done || true
else
    echo "${LOG_PREFIX} [4/4] ⚠️ 快照失败，跳过维护清理"
fi

# ─── 完成 ────────────────────────────────────────────────────────────────────
if [ "${SNAP_SUCCESS}" = true ]; then
    echo "=== ${LOG_PREFIX} ✅ 完成: $(date) ==="
else
    echo "=== ${LOG_PREFIX} ❌ 失败: $(date) ==="
    send_pushplus "[VPS-告警] 灾备快照失败" "您的服务器在尝试执行全量容器快照倒排备份时遇到致命错误，错误代码 ${SNAP_RC}。<br/>请立即登录服务器，使用 \`docker logs kopia\` 检查！<br/>时间: $(date)"
    exit 1
fi
