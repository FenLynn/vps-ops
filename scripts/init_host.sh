#!/bin/bash
# =============================================================================
# VPS-OPS v2.0 — 裸机初始化脚本 (Ubuntu 24.04 LTS 优化版)
# 功能: OS 检测、apt 国内镜像换源、依赖安装、Docker 国内安装、用户创建、
#       SSH 加固、防火墙、BBR 加速、目录创建、Tailscale、一键启动全部服务
#
# 网络策略: 全程优先使用国内镜像，规避 GFW 导致的拉取失败
# 用法: sudo bash scripts/init_host.sh
# =============================================================================

# 重要: 不使用 set -e，以便在非致命错误后继续执行
set -uo pipefail

# ─── DNS 修复 (解决国内解析 I/O 超时) ──────────────────────────────────────────
# 强制注入阿里云 DNS，防止 systemd-resolved 缓慢
echo "正在优化 DNS 设置..."
sed -i 's/^#DNS=/DNS=223.5.5.5 114.114.114.114/' /etc/systemd/resolved.conf 2>/dev/null || true
systemctl restart systemd-resolved 2>/dev/null || true
# 备份并强制设置临时 resolv.conf 以便立即生效
cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
echo -e "nameserver 223.5.5.5\nnameserver 114.114.114.114" > /etc/resolv.conf

# ─── 加载配置 ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "${PROJECT_DIR}/config.ini"

# 尝试加载 .env (如果存在)，以便获取 ADMIN_PASS, TAILSCALE_AUTH_KEY 等
if [ -f "${PROJECT_DIR}/.env" ]; then
    # 过滤掉注释并导出变量
    export $(grep -v '^#' "${PROJECT_DIR}/.env" | xargs)
fi

# ─── 消息推送与异常捕获 ────────────────────────────────────────────────────────────
send_pushplus() {
    local title="$1"
    local content="$2"
    if [ -n "${PUSHPLUS_TOKEN:-}" ]; then
        curl -s -X POST "http://www.pushplus.plus/send" \
            -H "Content-Type: application/json" \
            -d "{\"token\":\"${PUSHPLUS_TOKEN}\",\"title\":\"${title}\",\"content\":\"${content}\",\"template\":\"markdown\"}" > /dev/null
    fi
}
# 设置全局错误捕捉，如果脚本非正常退出，发送警告
trap 'rc=$?; if [ $rc -ne 0 ]; then send_pushplus "[VPS-告警] 初始化或重建异常中断" "开荒脚本在执行时发生致命错误退出！<br/>最后退出状态码: ${rc}。<br/>请立即通过云提供商后台 VNC 检查日志！"; fi' EXIT

# 禁用 Ubuntu 22.10+ 的 ssh.socket，将端口监听控制权还给 sshd_config
# 背景：Ubuntu 24.04 引入 systemd socket activation，ssh.socket 固守 22 端口，
#       导致 sshd_config 中的 Port 配置失效，自定义端口无法被监听。
# ⚠️  apt post-install 脚本（如安装 tailscale、fail2ban 等）可能重新激活 ssh.socket！
#       因此需要 mask 将其彻底屏蔽。
disable_ssh_socket_if_needed() {
    if systemctl is-active ssh.socket &>/dev/null || \
       systemctl is-enabled ssh.socket 2>/dev/null | grep -q "enabled"; then
        echo "  ⚙️  检测到 ssh.socket 激活 (Ubuntu 22.10+)，正在禁用以恢复传统端口控制..."
        systemctl disable --now ssh.socket 2>/dev/null || true
        echo "  ✅ ssh.socket 已禁用"
    fi
    # mask 是关键：彻底屏蔽 ssh.socket，防止 apt post-install 脚本（tailscale/fail2ban等）重新激活
    systemctl mask ssh.socket 2>/dev/null || true
    # 确保 ssh.service 为传统常驻进程模式并开机自启
    systemctl enable ssh.service 2>/dev/null || true
    echo "  ✅ ssh.socket 已 mask，端口控制权归还给 sshd_config"
}

# 核心路径
BASE_DIR="${BASE_DIR:-/opt/vps-dmz}"

echo "=== VPS-OPS v2.0 裸机初始化 (Ubuntu 24.04 优化) ==="
echo "项目目录: ${PROJECT_DIR}"
echo "部署目录: ${BASE_DIR}"
echo "SSH 端口: ${SSH_PORT}"
echo "Docker 网络: ${DOCKER_NET}"
echo "=============================================="

# ─── 前置检查 ─────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请以 root 身份运行此脚本"
    exit 1
fi

# ─── [1/12] 操作系统检测 ──────────────────────────────────────────────────────
echo ""
echo "[1/12] 检测操作系统..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "⚠️  未知操作系统，尝试 ubuntu 逻辑"
    OS="ubuntu"
    VER="24.04"
fi
echo "  ✅ 检测到: $OS $VER"

# ─── [2/12] 全局非交互适配 + apt 换国内源 ─────────────────────────────────────
echo ""
echo "[2/12] 配置系统环境..."

# 全局禁止所有交互式弹窗 (针对 Ubuntu 22.04/24.04)
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
# apt 静默冲突处理选项
APT_FLAGS="-y \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    -o APT::Get::Assume-Yes=true \
    -o APT::Install-Recommends=false"

# needrestart 静默配置 (Ubuntu 22+)
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    mkdir -p /etc/needrestart/conf.d
    cat > /etc/needrestart/conf.d/99-noninteractive.conf << 'EOF'
# 全自动重启所有需要更新的服务，不询问
$nrconf{restart} = 'a';
$nrconf{kernelhints} = 0;
EOF
    echo "  ✅ needrestart 已设为静默模式"
fi

# ─── Ubuntu: 换阿里云国内源 ───────────────────────────────────────────────────
if [ "$OS" = "ubuntu" ]; then
    echo "  - 换 apt 源为阿里云镜像..."

    # 备份原始 sources.list
    cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true

    # Ubuntu 24.04 (noble) 使用新的 DEB822 格式
    if [ "$VER" = "24.04" ]; then
        # 24.04 用 /etc/apt/sources.list.d/ubuntu.sources (DEB822 格式)
        cat > /etc/apt/sources.list.d/ubuntu-cn.sources << 'EOF'
Types: deb
URIs: https://mirrors.aliyun.com/ubuntu
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: https://mirrors.aliyun.com/ubuntu
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
        # 禁用官方 sources 避免冲突，但保留 sources.list 作为备份
        if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
            mv /etc/apt/sources.list.d/ubuntu.sources \
               /etc/apt/sources.list.d/ubuntu.sources.bak 2>/dev/null || true
        fi
        echo "  ✅ Ubuntu 24.04 apt 源已换为阿里云 (DEB822 格式)"
    else
        # Ubuntu 22.04 及更早版本
        CODENAME=$(lsb_release -sc 2>/dev/null || echo "jammy")
        cat > /etc/apt/sources.list << EOF
deb https://mirrors.aliyun.com/ubuntu/ ${CODENAME} main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${CODENAME}-updates main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${CODENAME}-security main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${CODENAME}-backports main restricted universe multiverse
EOF
        echo "  ✅ Ubuntu ${VER} apt 源已换为阿里云 (传统格式)"
    fi
fi

# ─── [3/12] 安装系统依赖 ──────────────────────────────────────────────────────
echo ""
echo "[3/12] 安装系统依赖..."
case "$OS" in
    ubuntu|debian)
        apt-get update -qq
        apt-get install ${APT_FLAGS} \
            curl wget git vim ufw fail2ban \
            uidmap slirp4netns unattended-upgrades \
            ca-certificates gnupg lsb-release jq \
            cron apt-transport-https software-properties-common
        FW_TOOL="ufw"
        AUTH_LOG="/var/log/auth.log"
        echo "  ✅ 系统依赖安装完成"
        ;;
    centos|rhel|almalinux|rocky|alinux)
        yum install -y epel-release
        yum makecache && yum install -y \
            curl wget git vim firewalld fail2ban \
            ca-certificates gnupg2 jq cronie
        FW_TOOL="firewalld"
        AUTH_LOG="/var/log/secure"
        echo "  ✅ 系统依赖安装完成"
        ;;
    *)
        echo "❌ 不支持的操作系统: $OS"
        exit 1
        ;;
esac

# ─── [4/12] 安装 Docker (国内源优先) ─────────────────────────────────────────
echo ""
echo "[4/12] 安装 Docker..."
if ! command -v docker &> /dev/null; then
    DOCKER_INSTALLED=false

    # 彻底清理可能导致冲突的旧源 (针对 Ubuntu 24.04 GPG 路径冲突优化)
    echo "  - 预防性清理旧 Docker 源配置..."
    rm -f /etc/apt/sources.list.d/docker*.list /etc/apt/keyrings/docker*
    apt-get update -qq &>/dev/null || true

    # 优先方式: get.docker.com + 阿里云镜像
    echo "  - 尝试 get.docker.com (阿里云镜像加速)..."
    if curl --connect-timeout 15 --max-time 60 -fsSL "https://get.docker.com" -o /tmp/get-docker.sh; then
        if sh /tmp/get-docker.sh --mirror Aliyun; then
            DOCKER_INSTALLED=true
            echo "  ✅ Docker 安装成功 (via get.docker.com + 阿里云)"
        fi
        rm -f /tmp/get-docker.sh
    fi

    # 备用方式: 直接添加阿里云 Docker CE repo
    if [ "$DOCKER_INSTALLED" = false ] && ([ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]); then
        echo "  - 备用: 阿里云 Docker CE apt 源..."
        install -m 0755 -d /etc/apt/keyrings
        # 使用 --batch 模式防止交互式报错
        curl --connect-timeout 15 --max-time 60 -fsSL \
            "https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg" \
            | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
            ${CODENAME} stable" \
            > /etc/apt/sources.list.d/docker-aliyun.list
        apt-get update -qq
        apt-get install ${APT_FLAGS} docker-ce docker-ce-cli containerd.io docker-compose-plugin && \
            DOCKER_INSTALLED=true && echo "  ✅ Docker 安装成功 (via 阿里云 apt)"
    fi

    if [ "$DOCKER_INSTALLED" = false ]; then
        echo "❌ Docker 安装失败，请手动安装"
        exit 1
    fi
else
    echo "  ✅ Docker 已安装: $(docker --version)"
fi

# ─── Docker daemon.json 国内镜像加速 ──────────────────────────────────────────
echo "  - 配置 Docker 镜像加速 (国内源)..."
mkdir -p /etc/docker

# 动态构建镜像列表，如果定义了 DOCKER_MIRROR 则置顶
MIRRORS="\"https://docker.m.daocloud.io\",\"https://docker.xuanyuan.me\", \"https://dockerproxy.cn\", \"https://docker.nju.edu.cn\""
if [ -n "${DOCKER_MIRROR:-}" ]; then
    echo "    📍 注入专属加速器: $DOCKER_MIRROR"
    MIRRORS="$MIRRORS, \"$DOCKER_MIRROR\""
fi

cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    $MIRRORS,
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl daemon-reload
systemctl enable --now docker
systemctl restart docker
echo "  ✅ Docker daemon 国内镜像加速已配置"

# ─── [5/12] 创建管理用户 ──────────────────────────────────────────────────────
echo ""
echo "[5/12] 创建用户 '${ADMIN_USER}'..."
if ! id "${ADMIN_USER}" &>/dev/null; then
    useradd -m -s /bin/bash ${ADMIN_USER}
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        usermod -aG sudo,docker ${ADMIN_USER}
    else
        usermod -aG wheel,docker ${ADMIN_USER}
    fi
    # 免密 sudo
    mkdir -p /etc/sudoers.d
    echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-vps-ops-user
    echo "  ✅ 用户 ${ADMIN_USER} 已创建"
else
    # 确保已加入 docker 组
    usermod -aG docker ${ADMIN_USER} 2>/dev/null || true
    echo "  ✅ 用户 ${ADMIN_USER} 已存在"
fi

# 迁移 SSH 密钥 (三源汇聚: Secrets / presets / root 迁移)
mkdir -p /home/${ADMIN_USER}/.ssh
AUTH_FILE="/home/${ADMIN_USER}/.ssh/authorized_keys"

if [ -n "${INJECT_SSH_PUBKEY:-}" ]; then
    echo "  - 从 GitHub Actions 注入 SSH 公钥..."
    echo "${INJECT_SSH_PUBKEY}" >> "${AUTH_FILE}"
fi

if [ -f "${PROJECT_DIR}/presets/authorized_keys" ]; then
    # 过滤掉注释行，只注入真实公钥
    grep -v '^\s*#' "${PROJECT_DIR}/presets/authorized_keys" | \
        grep -v '^\s*$' >> "${AUTH_FILE}" || true
    echo "  - 从 presets/authorized_keys 注入 SSH 公钥..."
fi

# 如果还是空的且 root 有密钥，则迁移 root 的
if [ ! -s "${AUTH_FILE}" ] && [ -f /root/.ssh/authorized_keys ]; then
    echo "  - 迁移 root 的 authorized_keys..."
    cp /root/.ssh/authorized_keys "${AUTH_FILE}"
fi

# 去重并修正权限
sort -u "${AUTH_FILE}" -o "${AUTH_FILE}" 2>/dev/null || true
chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.ssh
chmod 700 /home/${ADMIN_USER}/.ssh
chmod 600 "${AUTH_FILE}" 2>/dev/null || true

# ─── [6/12] SSH 初始化 (保持系统默认，加固交给 ssh_harden.sh) ─────────────────
echo ""
echo "[6/12] SSH 初始化 (Bootstrap 阶段: 不修改端口/认证策略)..."

# ⚠️ Bootstrap 只做最低限度处理：
#   - 保持系统默认 22 端口、root 可登录、密码认证均保留
#   - 公钥已从 presets/authorized_keys 注入，确保后续 ssh_harden.sh 能无密钥登入
#   - 完整的 SSH 加固（改端口、禁root、禁密码、Tailscale SSH）请在部署稳定后
#     手动执行：sudo bash scripts/ssh_harden.sh
disable_ssh_socket_if_needed
echo "  ✅ SSH 保持默认配置 (Port 22, 密码+公钥双认证)"  
echo "  💡 完整加固请创建稳定后手动执行: sudo bash /opt/vps-dmz/scripts/ssh_harden.sh"

# ─── [7/12] 防火墙配置 ────────────────────────────────────────────────────────
echo ""
echo "[7/12] 配置防火墙 ($FW_TOOL)..."
if [ "$FW_TOOL" = "ufw" ]; then
    ufw default deny incoming
    ufw default allow outgoing
    # Bootstrap 只放行默认 22（SSH 加固后由 ssh_harden.sh 添加自定义端口并移除 22）
    ufw allow 22/tcp             comment 'SSH-Default'
    ufw allow ${DERP_PORT}/tcp   comment 'DERP relay'
    ufw allow ${DERP_STUN_PORT}/udp comment 'DERP STUN'
    ufw allow from 127.0.0.1
    if [ "${NONINTERACTIVE:-false}" = "true" ]; then
        ufw --force enable
        echo "  ✅ UFW 已自动启用"
    else
        echo "  ✅ UFW 规则已写入，请手动执行: ufw --force enable"
    fi
elif [ "$FW_TOOL" = "firewalld" ]; then
    systemctl enable --now firewalld
    firewall-cmd --permanent --add-port=22/tcp
    firewall-cmd --permanent --add-port=${DERP_PORT}/tcp
    firewall-cmd --permanent --add-port=${DERP_STUN_PORT}/udp
    firewall-cmd --reload
    echo "  ✅ firewalld 配置完成"
fi

# ─── [8/12] 性能优化 ──────────────────────────────────────────────────────────
echo ""
echo "[8/12] 性能优化..."

# Swap 2G (针对 2C2G 低配 VPS)
if [ ! -f /swapfile ] && [ ! -b /dev/vdb1 ]; then
    echo "  - 创建 2G Swap..."
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile
    mkswap /swapfile -q
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    # 优化 swappiness (减少 swap 使用频率)
    grep -q 'vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
    echo "  ✅ Swap 2G 已创建"
fi

# BBR 拥塞控制 (Ubuntu 24.04 内核默认已支持)
if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || \
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || \
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p -q 2>/dev/null || true
    echo "  ✅ BBR 已启用"
fi

# lazydocker (通过 gh-proxy 代理访问 GitHub)
if ! command -v lazydocker &> /dev/null; then
    echo "  - 安装 lazydocker (via gh-proxy)..."
    curl --connect-timeout 15 --max-time 90 -fsSL \
        "https://gh-proxy.com/https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh" \
        | bash 2>/dev/null || echo "  ⚠️  lazydocker 安装跳过 (可后续手动安装)"
fi

# ─── [9/12] Fail2Ban ──────────────────────────────────────────────────────────
echo ""
echo "[9/12] 配置 Fail2Ban..."
# Bootstrap 阶段只监听默认 22 端口
# ssh_harden.sh 执行后会自动更新 Fail2Ban 规则以匹配新端口
cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled  = true
port     = 22
filter   = sshd
logpath  = ${AUTH_LOG}
maxretry = 3
bantime  = 86400
findtime = 600
EOF
systemctl enable --now fail2ban 2>/dev/null || true
systemctl restart fail2ban 2>/dev/null || true
echo "  ✅ Fail2Ban 已配置 (仅监听 22 端口，执行 ssh_harden.sh 后会自动更新)"

# ─── [10/12] 创建目录结构 & 同步文件 ─────────────────────────────────────────
echo ""
echo "[10/12] 创建目录结构: ${BASE_DIR}..."

mkdir -p \
    ${BASE_DIR}/data/acme \
    ${BASE_DIR}/data/uptime-kuma \
    ${BASE_DIR}/data/kopia-cache \
    ${BASE_DIR}/data/homepage \
    ${BASE_DIR}/logs/nginx \
    ${BASE_DIR}/config/nginx-relay \
    ${BASE_DIR}/config/fastapi-gateway \
    ${BASE_DIR}/scripts

# 权限修正 (部分容器以 UID 1000 运行)
chown -R 1000:1000 ${BASE_DIR}/data ${BASE_DIR}/logs

# 同步项目文件
echo "  - 同步项目文件..."
cp -f ${PROJECT_DIR}/compose/docker-compose.yml ${BASE_DIR}/docker-compose.yml
cp -f ${PROJECT_DIR}/config/nginx-relay/nginx.conf \
      ${BASE_DIR}/config/nginx-relay/nginx.conf 2>/dev/null || true
cp -rf ${PROJECT_DIR}/config/fastapi-gateway/* \
       ${BASE_DIR}/config/fastapi-gateway/ 2>/dev/null || true
cp -f ${PROJECT_DIR}/scripts/*.sh ${BASE_DIR}/scripts/
chmod +x ${BASE_DIR}/scripts/*.sh

# 用户预设 (vim/bashrc)
USER_HOME="/home/${ADMIN_USER}"

apply_user_presets() {
    local target_home=$1
    local target_user=$2
    
    if [ -f "${PROJECT_DIR}/presets/.vimrc" ]; then
        cp -f "${PROJECT_DIR}/presets/.vimrc" "${target_home}/.vimrc"
        chown ${target_user}:${target_user} "${target_home}/.vimrc"
        echo "  - .vimrc 已安装给 ${target_user}"
    fi

    if [ -f "${PROJECT_DIR}/presets/bashrc.append" ]; then
        if [ -f "${target_home}/.bashrc" ] && ! grep -q "vps-ops Custom Bash Presets" "${target_home}/.bashrc" 2>/dev/null; then
            cat "${PROJECT_DIR}/presets/bashrc.append" >> "${target_home}/.bashrc"
            echo "  - bashrc 已追加给 ${target_user}"
        fi
    fi
}

apply_user_presets "${USER_HOME}" "${ADMIN_USER}"
apply_user_presets "/root" "root"
echo "  ✅ 用户终端预设同步完成"

# ─── [11/12] 安装 Tailscale ───────────────────────────────────────────────────
echo ""
echo "[11/12] 配置 Tailscale..."
if ! command -v tailscale &> /dev/null; then
    echo "  - 安装 Tailscale..."
    # tailscale 官方脚本会自动使用正确的包源，对 Ubuntu 友好
    curl --connect-timeout 20 --max-time 120 -fsSL https://tailscale.com/install.sh | sh
fi

# 确保 tailscaled 正在运行
systemctl enable --now tailscaled 2>/dev/null || true

# Bootstrap 阶段只安装 Tailscale，不自动加入 Tailnet
# 加入 Tailnet + 激活 Tailscale SSH 由 ssh_harden.sh 统一管理
echo "  ✅ Tailscale 已安装，请在 ssh_harden.sh 中统一激活"
echo "  💡 手动加入: tailscale up --authkey=<KEY> --ssh"

# ─── [12/12] 加载 .env 并启动服务 ────────────────────────────────────────────
echo ""
echo "[12/12] 加载环境变量并启动服务..."

# 查找 .env
DOTENV_PATH=""
if [ -f "${PROJECT_DIR}/.env" ]; then
    DOTENV_PATH="${PROJECT_DIR}/.env"
elif [ -f "${BASE_DIR}/.env" ]; then
    DOTENV_PATH="${BASE_DIR}/.env"
fi

if [ -z "$DOTENV_PATH" ]; then
    echo "❌ 错误: 未找到 .env 文件!"
    echo "   请先执行: cp .env.example .env && nano .env"
    exit 1
fi

echo "  - 从 $DOTENV_PATH 加载密钥..."
set -a; source "$DOTENV_PATH"; set +a

# 链接 .env 到部署目录 (增加路径判断防止自链接警告)
REAL_SRC="$(realpath "$DOTENV_PATH")"
REAL_DEST="$(realpath "${BASE_DIR}/.env" 2>/dev/null || echo "${BASE_DIR}/.env")"
if [ "$REAL_SRC" != "$REAL_DEST" ]; then
    ln -sf "$REAL_SRC" "${BASE_DIR}/.env"
fi

# GHCR 登录 (用于拉取私有 GitHub Packages)
if [ -n "${GH_TOKEN:-}" ]; then
    echo "  - [鉴权] 尝试登录 ghcr.io..."
    echo "$GH_TOKEN" | docker login ghcr.io -u "${GITHUB_USER:-FenLynn}" --password-stdin 2>/dev/null || echo "    ⚠️  ghcr.io 登录失败，公共镜像不受影响"
fi

# 创建 Docker 网络
docker network create ${DOCKER_NET:-vps_tunnel_net} 2>/dev/null || true

# SSH 重启 (确保 Drop-in 变更生效，apt 安装期间 ssh.socket 可能被重新激活)
echo "  - 确认 SSH 就绪..."
disable_ssh_socket_if_needed
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    systemctl restart ssh.service 2>/dev/null || service ssh restart 2>/dev/null || true
else
    systemctl restart sshd 2>/dev/null || true
fi
echo "  ✅ SSH 服务已重启 (Port 22, 默认配置)"

# 设置 crontab
echo "  - 安装 crontab..."
CRON_BACKUP="0 3 * * * ${BASE_DIR}/scripts/backup_kopia.sh >> ${BASE_DIR}/logs/backup.log 2>&1"
CRON_PRUNE="0 4 * * * ${BASE_DIR}/scripts/prune.sh >> ${BASE_DIR}/logs/prune.log 2>&1"
(crontab -l 2>/dev/null | grep -v "backup_kopia.sh" | grep -v "prune.sh"; \
 echo "$CRON_BACKUP"; echo "$CRON_PRUNE") | crontab -

# 构建 FastAPI 网关镜像 (如果 Dockerfile 存在)
if [ -f "${BASE_DIR}/config/fastapi-gateway/Dockerfile" ]; then
    echo "  - 构建 FastAPI 网关镜像..."
    docker build -t vps-ops/fastapi-gateway:latest ${BASE_DIR}/config/fastapi-gateway/
fi

# ─── BDR: 自动灾备恢复 (基于 Kopia + R2) ──────────────────────────────────
if [ "${AUTO_RESTORE_FROM_R2:-true}" = "true" ] && [ -n "${R2_BUCKET:-}" ]; then
    echo ""
    echo "[BDR 灾备恢复] 检测到 AUTO_RESTORE_FROM_R2 开启..."
    # 检查核心业务文件是否已存在 (以 uptime-kuma 的 db 存在为准，防止误覆盖现有业务)
    if [ ! -f "${BASE_DIR}/data/uptime-kuma/kuma.db" ]; then
        echo "  - 判定当前为全新空载节点，尝试连入 Cloudflare R2..."
        cd ${BASE_DIR}
        # 先确保镜像拉取成功（最多重试 3 次，防止网络抖动 EOF 导致失败）
        for attempt in 1 2 3; do
            echo "  - ⬇️ 拉取 Kopia 镜像 (尝试 ${attempt}/3)..."
            if docker compose pull kopia 2>&1 | tee /tmp/kopia_pull.log; then
                echo "  ✅ 镜像下载成功"
                break
            fi
            if [ ${attempt} -eq 3 ]; then
                echo "  ❌ 致命错误：Kopia 镜像拉取在 3 次尝试后仍然失败（网络问题 EOF）！"
                cat /tmp/kopia_pull.log
                send_pushplus "[VPS-告警] Kopia 镜像下载失败" "拉取镜像时连续 3 次遭遇 EOF 中断，可能是宿主机网络不稳定。<br/>BDR 恢复已暂停，请稍后手动重试或检查网络连接。"
                exit 1
            fi
            echo "  ⚠️ 拉取失败，等待 10 秒后重试..."
            sleep 10
        done
        
        docker compose up -d kopia
        echo "  - ⏳ 等待 Kopia 与 R2 建立握手 (20秒)..."
        sleep 20
        
        # 🚨 终极防爆红线第一层：检查容器是否真正启动（区分镜像问题和配置问题）
        if ! docker ps --format '{{.Names}}' | grep -q "^kopia$"; then
            echo "  ❌ 致命错误：Kopia 容器启动失败（可能是镜像损坏或 entrypoint 异常）！"
            echo "     正在拉取 compose 服务日志..."
            echo "------------------- [ KOPIA COMPOSE LOGS ] -------------------"
            docker compose logs kopia 2>&1 | tail -40
            echo "------------------------------------------------------------"
            send_pushplus "[VPS-致命告警] Kopia 容器启动失败" "容器 kopia 启动后立即退出，可能是 R2 凭证错误或 entrypoint 异常。<br/>请查看 \`docker compose logs kopia\` 检查原因！"
            exit 1
        fi
        
        # 🚨 终极防爆红线第二层：检查容器内 Kopia 是否真正连入了 R2
        if ! docker exec kopia kopia repository status >/dev/null 2>&1; then
            echo "  ❌ 致命错误：Kopia 容器已启动，但无法连接至 R2 仓库！"
            echo "     很可能是 R2 密钥错误或 Endpoint URL 格式问题。"
            echo "------------------- [ KOPIA CRASH LOGS ] -------------------"
            docker logs kopia 2>&1 | tail -50
            echo "------------------------------------------------------------"
            send_pushplus "[VPS-致命告警] R2 库连接失败" "Kopia 容器已启动但连接 R2 时遭到拒绝，请检查 .env 中的 R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY / R2_ENDPOINT_URL 是否正确。<br/>BDR 恢复已强制暂停以保护云端数据！"
            docker compose stop kopia 2>/dev/null || true
            exit 1
        fi
        
        # 提取云端最新一次快照的 ID
        LATEST_SNAP=$(docker exec kopia kopia snapshot list --json 2>/dev/null | jq -r '.[-1].id')
        
        if [ -n "$LATEST_SNAP" ] && [ "$LATEST_SNAP" != "null" ]; then
            echo "  ✅ 在 R2 中发现可用快照 [$LATEST_SNAP]！开始全自动时空还原..."
            docker exec kopia kopia restore "$LATEST_SNAP" /source
            echo "  ✅ 数据解压与还原完美完成！"
            send_pushplus "[VPS] BDR 灾备恢复大成功" "节点已从 R2 云端快照 \`${LATEST_SNAP}\` 中完美重建所有业务数据！"
        else
            echo "  ⚠️ R2 中暂无历史快照，本台机器将作为全新节点开荒。"
            send_pushplus "[VPS] BDR 架构全新空载开荒" "检测到 R2 中毫无可用备份快照，VPS设备将作为全新主节点进行初始化开荒。"
        fi
        
        # 恢复完顺手停掉 kopia，等下面全量拉起
        docker compose stop kopia 2>/dev/null || true
    else
        echo "  ⚠️ 本地已有活数据结构，为保护现场，已自动阻断 R2 快照覆写。"
    fi
fi

# 🚀 启动全部服务
echo ""
echo "🚀 启动全部 Docker 服务..."
cd ${BASE_DIR}
# 拉取镜像时通过 daemon.json 中的国内源加速
docker compose pull --ignore-pull-failures
docker compose up -d

# --- 业务初始化配置 ---
echo "  - ⏳ 等待 Alist 启动 (15秒) 并在需要时设置初始密码..."
sleep 15
if [ -n "${ALIST_PASSWD:-}" ]; then
    # 尝试设置密码，如果因为数据库未就绪失败则不影响整体脚本退出
    docker exec alist ./alist admin set "${ALIST_PASSWD}" >/dev/null 2>&1 || echo "  ⚠️ Alist 密码设置可能未成功，请后续手动检查。"
    echo "  ✅ Alist 初始密码已根据 .env 自动设置完毕"
fi

echo ""
echo "=============================================="
echo "✅ VPS-OPS v2.0 部署完成!"
echo "=============================================="
echo "SSH 端口: 22 (默认，加固后由 ssh_harden.sh 修改为 ${SSH_PORT})"
echo "部署目录: ${BASE_DIR}"
echo ""
echo "⚠️  下一步操作:"
echo "  1. 在云控制台防火墙确认 22/TCP 已开放"
echo "  2. 在另一终端测试 SSH 可正常连接后，再执行 SSH 加固:"
echo "       sudo bash ${BASE_DIR}/scripts/ssh_harden.sh --dry-run  # 先预览"
echo "       sudo bash ${BASE_DIR}/scripts/ssh_harden.sh            # 再执行"
echo "  3. 证书手动签发 (需 acme daemon 已运行):"
echo "       sudo bash ${BASE_DIR}/scripts/cert_issue.sh --staging  # 先测试"
echo "       sudo bash ${BASE_DIR}/scripts/cert_issue.sh            # 再正式签"
echo "  4. 去 Cloudflare Zero Trust 配置 Tunnel 路由"
echo "  5. 查看容器状态: docker ps"
echo "=============================================="

# 发送收尾成功捷报
send_pushplus "[VPS] 🚀 开荒/重建部署全量完成" "您的服务器已经成功穿透封锁环境组装完毕，并已拉起所有业务容器。<br/>无状态堡垒机运行状态良好，网络畅通！"
