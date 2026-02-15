#!/bin/bash
# Prune Docker System (Images, Containers, Networks) daily
# Add to crontab: 0 4 * * * /nfs/vps-ops/scripts/prune.sh >> /var/log/docker-prune.log 2>&1

echo "=== Docker Prune Start: $(date) ==="
docker system prune -af --filter "until=168h"
docker volume prune -f
echo "=== Docker Prune End: $(date) ==="
