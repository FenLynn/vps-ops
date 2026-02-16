#!/bin/bash
set -e

# Load Configuration
source config.ini

echo "=== vps-ops Host Initialization (Standard Linux Edition) ==="
echo "Target User: ${ADMIN_USER}"
echo "SSH Port: ${SSH_PORT}"
echo "Docker Root: ${DOCKER_ROOT}"
echo "=========================================================="

# Check for root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# 1. OS Detection
echo "[1/8] Detecting OS..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "Unknown OS. Defaulting to generic logic."
    OS="unknown"
fi

echo "Detected OS: $OS ($VER)"

# 2. Package Management & Dependencies
echo "[2/8] Installing Dependencies..."
case "$OS" in
    ubuntu|debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update && apt-get install -y \
            curl wget git ufw fail2ban \
            uidmap slirp4netns unattended-upgrades \
            ca-certificates gnupg lsb-release
        FW_TOOL="ufw"
        AUTH_LOG="/var/log/auth.log"
        ;;
    centos|rhel|almalinux|rocky|alinux)
        yum install -y epel-release
        yum makecache && yum install -y \
            curl wget git firewalld fail2ban \
            ca-certificates gnupg2
        FW_TOOL="firewalld"
        AUTH_LOG="/var/log/secure"
        # Ensure EPEL is available for fail2ban if needed (usually needed for CentOS 7/8)
        # yum install -y epel-release && yum install -y fail2ban
        ;;
    *)
        echo "Unsupported OS for automatic package installation. Please install dependencies manually."
        exit 1
        ;;
esac

# --- Optional Git Proxy (Manual Enable) ---
# echo "Setting Git Proxy..."
# git config --global http.proxy socks5://192.168.12.21:50170
# git config --global https.proxy socks5://192.168.12.21:50170

# 3. Configure Docker (Mainland Mirrors)
echo "[3/8] Configuring Docker..."
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    # Try multiple sources for the installation script to handle networking hurdles
    INSTALL_SUCCESS=false
    for SCR_URL in "https://get.docker.com" "https://test.docker.com" "https://mirror.azure.cn/docker-ce/linux/debian/gpg"; do
        echo "Trying to fetch installation script from ${SCR_URL}..."
        if [ "$SCR_URL" = "https://get.docker.com" ]; then
            curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh --mirror Aliyun && INSTALL_SUCCESS=true && break
        else
            # Backup: Use Aliyun's specific installation method if get.docker.com is blocked
            curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo || true
            yum install -y docker-ce docker-ce-cli containerd.io || apt-get install -y docker-ce docker-ce-cli containerd.io && INSTALL_SUCCESS=true && break
        fi
    done

    if [ "$INSTALL_SUCCESS" = false ]; then
        echo "❌ Docker installation failed from all sources. Please install manually."
        exit 1
    fi
fi

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

# 4. User Creation & SSH Keys
echo "[4/8] Setting up User '${ADMIN_USER}'..."
if ! id "${ADMIN_USER}" &>/dev/null; then
    useradd -m -s /bin/bash ${ADMIN_USER}
    # Add to appropriate groups
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        usermod -aG sudo,docker ${ADMIN_USER}
    else
        usermod -aG wheel,docker ${ADMIN_USER}
    fi
    echo "${ADMIN_USER} created."
    
    # Allow NOPASSWD for automation
    mkdir -p /etc/sudoers.d
    echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-vps-ops-user
fi

# Migrate SSH Keys
mkdir -p /home/${ADMIN_USER}/.ssh
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/${ADMIN_USER}/.ssh/authorized_keys
fi
chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.ssh
chmod 700 /home/${ADMIN_USER}/.ssh
chmod 600 /home/${ADMIN_USER}/.ssh/authorized_keys

# 5. SSH Hardening
echo "[5/8] Hardening SSH..."
# Safer idempotent port replacement: replaces any #Port or Port followed by numbers
sed -i -E "s/^#?Port [0-9]+/Port ${SSH_PORT}/" /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/g' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

# SELinux Handling (for CentOS/RHEL)
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    echo "  - SELinux detected. Adding port ${SSH_PORT} to SSH..."
    yum install -y policycoreutils-python-utils &> /dev/null || apt-get install -y policycoreutils-python-utils &> /dev/null
    semanage port -a -t ssh_port_t -p tcp ${SSH_PORT} 2>/dev/null || semanage port -m -t ssh_port_t -p tcp ${SSH_PORT}
fi

# Ensure service directory exists
mkdir -p /var/run/sshd

# 6. Network & Firewall
echo "[6/8] Configuring Firewall ($FW_TOOL) & Docker Network..."
# Ensure default network exists
docker network create ${DOCKER_NET:-vps-net} 2>/dev/null || true

if [ "$FW_TOOL" = "ufw" ]; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ${SSH_PORT}/tcp
    ufw allow ${DERP_PORT}/tcp
    ufw allow ${DERP_STUN_PORT}/udp
    ufw allow from 127.0.0.1
    # ufw --force enable
elif [ "$FW_TOOL" = "firewalld" ]; then
    systemctl enable --now firewalld
    firewall-cmd --permanent --add-port=${SSH_PORT}/tcp
    firewall-cmd --permanent --add-port=${DERP_PORT}/tcp
    firewall-cmd --permanent --add-port=${DERP_STUN_PORT}/udp
    firewall-cmd --reload
fi

# 7. Performance & Tools
echo "[7/8] Tuning Performance..."
# Swap
if [ ! -f /swapfile ] && [ ! -b /dev/vdb1 ]; then # Basic check
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# BBR
if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
fi

# Lazydocker (Optional, uses mirror for China)
if ! command -v lazydocker &> /dev/null; then
    echo "  - Attempting to install lazydocker (via gh-proxy mirror)..."
    # Added timeout and fallback mirror (gh-proxy.com is usually reliable)
    curl --connect-timeout 10 --max-time 60 -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash || echo "  ! Failed to install lazydocker, skipping..."
fi

# 8. Fail2Ban
echo "[8/8] Configuring Fail2Ban..."
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

# Create Data Directories
echo "[8/9] Creating Directories at ${DOCKER_ROOT}..."
mkdir -p ${DOCKER_ROOT}/global/certs
mkdir -p ${DOCKER_ROOT}/stable/new-api
mkdir -p ${DOCKER_ROOT}/stable/uptime-kuma
mkdir -p ${DOCKER_ROOT}/stable/backups
mkdir -p ${DOCKER_ROOT}/infra/acme
chown -R ${ADMIN_USER}:${ADMIN_USER} ${DOCKER_ROOT}

# 9. Apply User Presets (Shell & Vim)
echo "[9/9] Applying User Presets..."
USER_HOME="/home/${ADMIN_USER}"

# Vimrc
if [ -f "presets/.vimrc" ]; then
    cp presets/.vimrc "${USER_HOME}/.vimrc"
    chown ${ADMIN_USER}:${ADMIN_USER} "${USER_HOME}/.vimrc"
    echo "  - Installed .vimrc"
fi

# Bashrc Append
if [ -f "presets/bashrc.append" ]; then
    # Ensure idempodent append
    if ! grep -q "vps-ops Custom Bash Presets" "${USER_HOME}/.bashrc" 2>/dev/null; then
        cat presets/bashrc.append >> "${USER_HOME}/.bashrc"
        echo "  - Appended bashrc.append"
    fi
fi

# 8. Final Automation & Login
echo "[8/8] Finalizing Automation..."

# Source secrets from .env
DOTENV_PATH=""
if [ -f ".env" ]; then
    DOTENV_PATH=".env"
elif [ -f "../.env" ]; then
    DOTENV_PATH="../.env"
fi

if [ -n "$DOTENV_PATH" ]; then
    echo "  - Sourcing secrets from $DOTENV_PATH..."
    set -a
    source "$DOTENV_PATH"
    set +a

    # SYMLINK .env for Docker Compose interpolation (Fixes "variable not set" warnings)
    # Compose looks for .env in the CURRENT folder, not parent.
    echo "  - Linking .env to service subdirectories..."
    ln -sf "$(realpath $DOTENV_PATH)" 00-infra/.env
    ln -sf "$(realpath $DOTENV_PATH)" 01-stable/.env
else
    echo "  ❌ ERROR: .env file NOT FOUND in $(pwd) or parent!"
    echo "  You MUST create .env from .env.example and configure it before running."
    echo "  Command: cp .env.example .env && nano .env"
    exit 1
fi

# Automated Docker Login (if GH_TOKEN is present)
if [ -n "$GH_TOKEN" ]; then
    echo "  - Found GH_TOKEN. Attempting automated login to ghcr.io..."
    echo "$GH_TOKEN" | docker login ghcr.io -u ${ADMIN_USER:-FenLynn} --password-stdin
else
    echo "  - GH_TOKEN not found in environment. Skipping login."
fi

# SSH Restart (Applying changes)
echo "  - Restarting SSH service..."
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    systemctl restart ssh || service ssh restart
else
    systemctl restart sshd
fi

echo "=== Initialization Complete ==="
echo "Detected OS: $OS"
echo "SSH Port: ${SSH_PORT}"
echo "----------------------------------------------------------"
echo "🚀 One-Key Deployment Sequence:"
echo "1. Verify SSH: You are now using port ${SSH_PORT}."
echo ""
echo "# To start everything, run these (already configured):"
echo "# cd 00-infra && docker compose up -d"
echo "# cd 01-stable && docker compose up -d"
echo ""
echo "⚠️  CRITICAL: OPEN PORT ${SSH_PORT} IN YOUR VPS CLOUD CONSOLE FIREWALL!"
echo "----------------------------------------------------------"

# FINAL DEPLOYMENT (One-Key Start)
echo "🚀 Starting Services Layer 0 (Infrastructure)..."
cd 00-infra && docker compose up -d

echo "⏳ Waiting for acme-init to finish (Certificate generation)..."
# Wait for container to exit
until [ "$(docker inspect -f '{{.State.Running}}' acme-init 2>/dev/null)" == "false" ]; do
    sleep 2
done

# VERIFY if certificate actually exists AND is valid
CERT_DOMAIN=$(grep DERP_DOMAIN .env | cut -d '=' -f2)
CERT_FILE="${DOCKER_ROOT}/global/certs/${CERT_DOMAIN}/${CERT_DOMAIN}.crt"
if [ ! -f "$CERT_FILE" ]; then
    echo "❌ CRITICAL: Certificate file not found: $CERT_FILE"
    echo "   Please check 'docker logs acme-init' for details."
    exit 1
fi
if [ ! -s "$CERT_FILE" ] || ! grep -q "BEGIN CERTIFICATE" "$CERT_FILE"; then
    echo "❌ CRITICAL: Certificate file is empty or invalid: $CERT_FILE"
    echo "   This usually means LetsEncrypt rate limit was hit or DNS verification failed."
    echo "   Please check 'docker logs acme-init' for details."
    exit 1
fi
echo "✅ acme-init finished and certificate verified."

echo "🚀 Starting Services Layer 1 (Business)..."
cd ../01-stable && docker compose up -d

echo "----------------------------------------------------------"
echo "✅ Deployment Successful! Check status with 'docker ps'"
echo "----------------------------------------------------------"
