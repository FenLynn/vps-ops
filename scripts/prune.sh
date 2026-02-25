#!/bin/bash
# Prune Docker System (Images, Containers, Networks) daily
# Add to crontab: 0 4 * * * /opt/vps-dmz/scripts/prune.sh >> /opt/vps-dmz/logs/prune.log 2>&1
# ⚠️ 注意: volume prune 不清理 kopia-cache / kopia-config 等命名卷
#          使用 --filter label 方式可按需保护特定卷（当前版本跳过卷清理以防误伤）

echo "=== Docker Prune Start: $(date) ==="
docker system prune -af --filter "until=168h"
# 🚫 故意不执行 docker volume prune：kopia 等服务的命名卷不该被自动清理
# 如需手动清理游离卷，请在确认安全后执行: docker volume prune -f
echo "=== Docker Prune End: $(date) ==="
