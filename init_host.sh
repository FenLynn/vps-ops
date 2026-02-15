#!/bin/bash
set -e

# Load Configuration
source config.ini

echo "=== vps-ops Host Initialization (Mainland China Edition) ==="
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

# 3. Configure Docker (Mainland Mirrors)
echo "[3/8] Configuring Docker..."
if ! command -v docker &> /dev/null; then
    echo "Installing Docker via get.docker.com..."
    curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
fi

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.nju.edu.cn",
    "https://dockerproxy.cn",
    "https://hub.rat.dev",
    "https://docker.m.daocloud.io"
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

# Ensure service directory exists
mkdir -p /var/run/sshd

# 6. Network & Firewall
echo "[6/8] Configuring Firewall ($FW_TOOL)..."
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

# Also apply to root for convenience
cp presets/.vimrc "/root/.vimrc" 2>/dev/null || true
if ! grep -q "vps-ops Custom Bash Presets" "/root/.bashrc" 2>/dev/null; then
    cat presets/bashrc.append >> "/root/.bashrc" 2>/dev/null || true
fi

echo "=== Initialization Complete ==="
echo "Detected OS: $OS"
echo "SSH Port has been set to: ${SSH_PORT}"
echo "Firewall ($FW_TOOL) has been configured."
echo "----------------------------------------------------------"
echo "Next Steps:"
echo "1. Verify SSH config: sshd -t"
echo "2. Restart SSH: systemctl restart sshd"
echo "3. Enable Firewall: ($FW_TOOL enable/start)"
echo "4. LOGIN VIA NEW PORT ${SSH_PORT} AS USER ${ADMIN_USER} BEFORE CLOSING THIS SESSION!"
