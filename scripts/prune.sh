#!/bin/bash
# Prune Docker System daily — 仅清理悬挂镜像和无主容器/网络
# Add to crontab: 0 4 * * * /opt/vps-dmz/scripts/prune.sh >> /opt/vps-dmz/logs/prune.log 2>&1

# ⚠️ 重要: 不使用 -a 参数！-a 会删除所有未被使用的镜像，包括自建的
# vps-ops/fastapi-gateway:latest 等，导致下次 compose up 时需重新 build！

BASE_DIR="${BASE_DIR:-/opt/vps-dmz}"

echo "=== Docker Prune Start: $(date) ==="

# 仅清理悬挂 (dangling) 镜像 + 无主网络（不加 --volumes 保护数据卷）
# 🚨 警告: 严禁加入 `docker container prune`! 否则意外停止的业务容器（或正在更新、或刚跑完的一次性初始化容器）会被永久无情删除！
docker image prune -f
docker network prune -f

# 🚫 故意不执行 docker volume prune：kopia 等服务的命名卷不该被自动清理
# 如需手动清理游离卷：docker volume prune -f

echo "=== Docker Prune End: $(date) ==="
