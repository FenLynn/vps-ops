#!/bin/bash
# =============================================================================
# VPS-OPS v2.0 — 裸机初始化脚本
# 功能: OS 检测、依赖安装、Docker 配置、用户创建、SSH 加固、防火墙、
#       BBR 加速、目录创建、Kopia 灾难恢复、一键启动全部服务
# 用法: sudo bash scripts/init_host.sh
# =============================================================================

set -e

# ─── 加载配置 ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "${PROJECT_DIR}/config.ini"

# 核心路径
BASE_DIR="${BASE_DIR:-/opt/vps-dmz}"

echo "=== VPS-OPS v2.0 裸机初始化 ==="
echo "项目目录: ${PROJECT_DIR}"
echo "部署目录: ${BASE_DIR}"
echo "SSH 端口: ${SSH_PORT}"
echo "Docker 网络: ${DOCKER_NET}"
echo "=================================="

# ─── 前置检查 ─────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请以 root 身份运行此脚本"
    exit 1
fi

# ─── [1/10] 操作系统检测 ─────────────────────────────────────────────────────
echo "[1/12] 检测操作系统..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "未知操作系统，使用通用逻辑"
    OS="unknown"
fi
echo "检测到: $OS ($VER)"

# ─── [2/10] 安装依赖 ─────────────────────────────────────────────────────────
echo "[2/12] 安装系统依赖..."
case "$OS" in
    ubuntu|debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update && apt-get install -y \
            curl wget git ufw fail2ban \
            uidmap slirp4netns unattended-upgrades \
            ca-certificates gnupg lsb-release jq
        FW_TOOL="ufw"
        AUTH_LOG="/var/log/auth.log"
        ;;
    centos|rhel|almalinux|rocky|alinux)
        yum install -y epel-release
        yum makecache && yum install -y \
            curl wget git firewalld fail2ban \
            ca-certificates gnupg2 jq
        FW_TOOL="firewalld"
        AUTH_LOG="/var/log/secure"
        ;;
    *)
        echo "❌ 不支持的操作系统: $OS"
        exit 1
        ;;
esac

# ─── [3/10] 安装 Docker ─────────────────────────────────────────────────────
echo "[3/12] 配置 Docker..."
if ! command -v docker &> /dev/null; then
    echo "安装 Docker..."
    INSTALL_SUCCESS=false
    for SCR_URL in "https://get.docker.com" "https://test.docker.com"; do
        echo "尝试: ${SCR_URL}..."
        if curl -fsSL "$SCR_URL" -o get-docker.sh && sh get-docker.sh --mirror Aliyun; then
            INSTALL_SUCCESS=true
            rm -f get-docker.sh
            break
        fi
    done

    if [ "$INSTALL_SUCCESS" = false ]; then
        # 备用: 阿里云源
        curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo 2>/dev/null || true
        yum install -y docker-ce docker-ce-cli containerd.io 2>/dev/null || \
        apt-get install -y docker-ce docker-ce-cli containerd.io 2>/dev/null || {
            echo "❌ Docker 安装失败，请手动安装"
            exit 1
        }
    fi
fi

# Docker 镜像加速
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.xuanyuan.me",
    "https://docker.1ms.run",
    "https://dockerproxy.cn",
    "https://docker.nju.edu.cn"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
systemctl daemon-reload
systemctl enable --now docker
systemctl restart docker

# ─── [4/10] 创建管理用户 ─────────────────────────────────────────────────────
echo "[4/12] 创建用户 '${ADMIN_USER}'..."
if ! id "${ADMIN_USER}" &>/dev/null; then
    useradd -m -s /bin/bash ${ADMIN_USER}
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        usermod -aG sudo,docker ${ADMIN_USER}
    else
        usermod -aG wheel,docker ${ADMIN_USER}
    fi
    echo "${ADMIN_USER} 已创建"

    # 免密 sudo
    mkdir -p /etc/sudoers.d
    echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-vps-ops-user
fi

# 迁移 SSH 密钥到 sudor 用户
# 优先使用 INJECT_SSH_PUBKEY (来自 GitHub Actions bootstrap.yml)
# 如果没有，则将 root 的现有 authorized_keys 复制迁移
mkdir -p /home/${ADMIN_USER}/.ssh
if [ -n "${INJECT_SSH_PUBKEY:-}" ]; then
    echo "  - 从 GitHub Actions 注入 SSH 公钥到 ${ADMIN_USER}..."
    echo "${INJECT_SSH_PUBKEY}" >> /home/${ADMIN_USER}/.ssh/authorized_keys
elif [ -f /root/.ssh/authorized_keys ]; then
    echo "  - 迁移 root 的 authorized_keys 到 ${ADMIN_USER}..."
    cp /root/.ssh/authorized_keys /home/${ADMIN_USER}/.ssh/authorized_keys
fi
chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.ssh
chmod 700 /home/${ADMIN_USER}/.ssh
chmod 600 /home/${ADMIN_USER}/.ssh/authorized_keys 2>/dev/null || true

# ─── [5/10] SSH 加固 ─────────────────────────────────────────────────────────
echo "[5/12] 加固 SSH..."
sed -i -E "s/^#?Port [0-9]+/Port ${SSH_PORT}/" /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/g' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

# SELinux 处理
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    echo "  - SELinux: 添加端口 ${SSH_PORT}..."
    yum install -y policycoreutils-python-utils &>/dev/null || true
    semanage port -a -t ssh_port_t -p tcp ${SSH_PORT} 2>/dev/null || \
        semanage port -m -t ssh_port_t -p tcp ${SSH_PORT} 2>/dev/null || true
fi

mkdir -p /var/run/sshd

# ─── [6/10] 防火墙配置 ───────────────────────────────────────────────────────
echo "[6/12] 配置防火墙 ($FW_TOOL)..."
if [ "$FW_TOOL" = "ufw" ]; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ${SSH_PORT}/tcp
    ufw allow ${DERP_PORT}/tcp
    ufw allow ${DERP_STUN_PORT}/udp
    ufw allow from 127.0.0.1
    # GitOps/NONINTERACTIVE 模式下自动开启 UFW
    if [ "${NONINTERACTIVE:-false}" = "true" ]; then
        ufw --force enable
        echo "  - UFW 已自动启用 (NONINTERACTIVE 模式)"
    else
        echo "  - UFW 规则已写入。请手动执行: ufw --force enable"
    fi
elif [ "$FW_TOOL" = "firewalld" ]; then
    systemctl enable --now firewalld
    firewall-cmd --permanent --add-port=${SSH_PORT}/tcp
    firewall-cmd --permanent --add-port=${DERP_PORT}/tcp
    firewall-cmd --permanent --add-port=${DERP_STUN_PORT}/udp
    firewall-cmd --reload
fi

# ─── [7/10] 性能优化 ─────────────────────────────────────────────────────────
echo "[7/12] 性能优化..."

# Swap (2G)
if [ ! -f /swapfile ] && [ ! -b /dev/vdb1 ]; then
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# BBR
if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
fi

# lazydocker (可选)
if ! command -v lazydocker &> /dev/null; then
    echo "  - 安装 lazydocker..."
    curl --connect-timeout 10 --max-time 60 -fsSL \
        https://gh-proxy.com/https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh \
        | bash || echo "  ⚠️ lazydocker 安装跳过"
fi

# ─── [8/10] Fail2Ban ─────────────────────────────────────────────────────────
echo "[8/12] 配置 Fail2Ban..."
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = ${AUTH_LOG}
maxretry = 3
bantime = 86400
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

# ─── [9/10] 创建部署目录 ─────────────────────────────────────────────────────
echo "[9/12] 创建目录结构: ${BASE_DIR}..."

# 核心四维目录
mkdir -p ${BASE_DIR}/data/acme
mkdir -p ${BASE_DIR}/data/new-api
mkdir -p ${BASE_DIR}/data/uptime-kuma
mkdir -p ${BASE_DIR}/data/kopia-cache
mkdir -p ${BASE_DIR}/data/dockge
mkdir -p ${BASE_DIR}/data/homarr/configs
mkdir -p ${BASE_DIR}/data/homarr/icons
mkdir -p ${BASE_DIR}/logs/new-api
mkdir -p ${BASE_DIR}/logs/nginx
mkdir -p ${BASE_DIR}/config/nginx-relay
mkdir -p ${BASE_DIR}/config/fastapi-gateway
mkdir -p ${BASE_DIR}/scripts

# 权限修正 (部分容器以 UID 1000 运行)
chown -R 1000:1000 ${BASE_DIR}/data ${BASE_DIR}/logs

# 将仓库内容同步到部署目录
echo "  - 同步项目文件..."
cp -f ${PROJECT_DIR}/compose/docker-compose.yml ${BASE_DIR}/docker-compose.yml
cp -f ${PROJECT_DIR}/config/nginx-relay/nginx.conf ${BASE_DIR}/config/nginx-relay/nginx.conf 2>/dev/null || true
cp -rf ${PROJECT_DIR}/config/fastapi-gateway/* ${BASE_DIR}/config/fastapi-gateway/ 2>/dev/null || true
cp -f ${PROJECT_DIR}/scripts/*.sh ${BASE_DIR}/scripts/
chmod +x ${BASE_DIR}/scripts/*.sh

# 用户预设
USER_HOME="/home/${ADMIN_USER}"
if [ -f "${PROJECT_DIR}/presets/.vimrc" ]; then
    cp "${PROJECT_DIR}/presets/.vimrc" "${USER_HOME}/.vimrc"
    chown ${ADMIN_USER}:${ADMIN_USER} "${USER_HOME}/.vimrc"
    echo "  - .vimrc 已安装"
fi
if [ -f "${PROJECT_DIR}/presets/bashrc.append" ]; then
    if ! grep -q "vps-ops Custom Bash Presets" "${USER_HOME}/.bashrc" 2>/dev/null; then
        cat "${PROJECT_DIR}/presets/bashrc.append" >> "${USER_HOME}/.bashrc"
        echo "  - bashrc 已追加"
    fi
fi

# ─── [10/12] 安装 Tailscale ──────────────────────────────────────────────────
echo "[10/12] 配置 Tailscale..."
if ! command -v tailscale &> /dev/null; then
    echo "  - 安装 Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# 确保 tailscaled 正在运行
systemctl enable --now tailscaled 2>/dev/null || true

# 如果提供了 Auth Key，自动加入 Tailnet
if [ -n "${TAILSCALE_AUTH_KEY:-}" ]; then
    echo "  - 自动加入 Tailscale 网络..."
    tailscale up --authkey="${TAILSCALE_AUTH_KEY}" --accept-routes 2>/dev/null || {
        # 可能已经登录过了
        echo "  ⚠️ tailscale up 失败 (可能已加入网络)"
        tailscale status || true
    }
elif ! tailscale status &>/dev/null; then
    echo "  ⚠️ 警告: TAILSCALE_AUTH_KEY 未设置且尚未登录 Tailscale!"
    echo "     DERP --verify-clients 和 nginx-relay 需要 Tailscale。"
    echo "     请手动执行: tailscale up"
fi

# ─── [11/12] 加载 .env 并启动 ────────────────────────────────────────────────
echo "[11/12] 加载环境变量并启动服务..."

# 查找 .env
DOTENV_PATH=""
if [ -f "${PROJECT_DIR}/.env" ]; then
    DOTENV_PATH="${PROJECT_DIR}/.env"
elif [ -f "${BASE_DIR}/.env" ]; then
    DOTENV_PATH="${BASE_DIR}/.env"
fi

if [ -z "$DOTENV_PATH" ]; then
    echo "❌ 错误: 未找到 .env 文件!"
    echo "请先执行: cp .env.example .env && nano .env"
    exit 1
fi

echo "  - 从 $DOTENV_PATH 加载密钥..."
set -a
source "$DOTENV_PATH"
set +a

# 链接 .env 到部署目录
ln -sf "$(realpath $DOTENV_PATH)" "${BASE_DIR}/.env"

# GHCR 登录
if [ -n "$GH_TOKEN" ]; then
    echo "  - 登录 ghcr.io..."
    echo "$GH_TOKEN" | docker login ghcr.io -u ${ADMIN_USER:-FenLynn} --password-stdin
fi

# 创建 Docker 网络
docker network create ${DOCKER_NET:-vps_tunnel_net} 2>/dev/null || true

# SSH 重启
echo "  - 重启 SSH..."
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    systemctl restart ssh || service ssh restart
else
    systemctl restart sshd
fi

# 设置定时任务
echo "  - 安装 crontab..."
CRON_BACKUP="0 3 * * * ${BASE_DIR}/scripts/backup_kopia.sh >> ${BASE_DIR}/logs/backup.log 2>&1"
CRON_PRUNE="0 4 * * * ${BASE_DIR}/scripts/prune.sh >> ${BASE_DIR}/logs/prune.log 2>&1"
(crontab -l 2>/dev/null | grep -v "backup_kopia.sh" | grep -v "prune.sh"; echo "$CRON_BACKUP"; echo "$CRON_PRUNE") | crontab -

# 构建 FastAPI 网关镜像 (如果 Dockerfile 存在)
if [ -f "${BASE_DIR}/config/fastapi-gateway/Dockerfile" ]; then
    echo "  - 构建 FastAPI 网关镜像..."
    docker build -t vps-ops/fastapi-gateway:latest ${BASE_DIR}/config/fastapi-gateway/
fi

# ─── [12/12] 启动全部服务 ─────────────────────────────────────────────────────
echo ""
echo "🚀 [12/12] 启动全部服务..."
cd ${BASE_DIR}
docker compose pull --ignore-pull-failures
docker compose up -d

echo ""
echo "=========================================="
echo "✅ VPS-OPS v2.0 部署完成!"
echo "=========================================="
echo "SSH 端口: ${SSH_PORT}"
echo "部署目录: ${BASE_DIR}"
echo ""
echo "⚠️ 重要提醒:"
echo "  1. 在云控制台防火墙开放端口 ${SSH_PORT}/TCP"
echo "  2. 去 Cloudflare Zero Trust 配置 Tunnel 路由"
echo "  3. 查看容器状态: docker ps"
echo "=========================================="
