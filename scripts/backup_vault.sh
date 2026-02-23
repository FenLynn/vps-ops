#!/bin/bash
# =============================================================================
# VPS-OPS — Vaultwarden SQLite 热备份 + Kopia 快照
# =============================================================================
# 用途：在 Kopia 快照前执行 SQLite 热备份，确保密码库数据原子性一致。
#       热备份使用 SQLite 官方 .backup 命令，无需停服，输出为无 WAL 的干净单文件。
#
# 布置 crontab (宿主机执行):
#   # 每 6 小时备份一次 Vault（全量快照每天由 backup_all.sh 触发）
#   0 */6 * * * /opt/vps-dmz/scripts/backup_vault.sh >> /opt/vps-dmz/logs/backup_vault.log 2>&1
#
# 迁移 Vault 到新机器:
#   1. kopia restore <snapshot-id> /target --path /source/vaultwarden
#   2. 取出 /target/db.backup.sqlite3，rename 为 db.sqlite3 放到新机器 /data/
#   3. 启动新机器的 vaultwarden 容器即可
# =============================================================================

set -euo pipefail

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
echo "[$TIMESTAMP] 🔐 Vaultwarden 热备份开始..."

# ─── Step 1：SQLite 官方热备份（不停服，原子一致性）────────────────────────
# .backup 命令会创建一个 checkpoint 后的干净副本，不依赖 WAL 文件即可完整恢复
docker exec vaultwarden sqlite3 /data/db.sqlite3 ".backup /data/db.backup.sqlite3"

if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] ❌ SQLite 热备份失败，跳过 Kopia 快照，请检查 vaultwarden 容器状态"
    exit 1
fi

echo "[$TIMESTAMP] ✅ SQLite 热备份完成 → /data/vaultwarden/db.backup.sqlite3"

# ─── Step 2：触发 Kopia 对 vaultwarden 目录的专属快照 ───────────────────────
docker exec kopia kopia snapshot create /source/vaultwarden

echo "[$TIMESTAMP] ✅ Kopia vault 快照完成"
echo "[$TIMESTAMP] 📋 最近 3 条 vault 快照:"
docker exec kopia kopia snapshot list /source/vaultwarden --max-results 3
