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

# 1. System Update & Dependencies
echo "[1/7] Updating System..."
apt-get update && apt-get install -y \
    curl wget git ufw fail2ban \
    uidmap slirp4netns \
    unattended-upgrades \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

# 2. Configure Docker (Mainland Mirrors)
echo "[2/7] Configuring Docker..."
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
fi

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com",
    "https://mirror.baidubce.com",
    "https://docker.nju.edu.cn"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
systemctl daemon-reload
systemctl restart docker

# 3. User Creation & SSH Keys
echo "[3/7] Setting up User '${ADMIN_USER}'..."
if ! id "${ADMIN_USER}" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo,docker ${ADMIN_USER}
    echo "${ADMIN_USER} created."
    
    # Allow NOPASSWD for automation (Optional, but requested in ADD)
    echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-cloud-init-users
fi

# Migrate SSH Keys
mkdir -p /home/${ADMIN_USER}/.ssh
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/${ADMIN_USER}/.ssh/authorized_keys
fi
chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.ssh
chmod 700 /home/${ADMIN_USER}/.ssh
chmod 600 /home/${ADMIN_USER}/.ssh/authorized_keys

# 4. SSH Hardening
echo "[4/7] Hardening SSH..."
sed -i "s/#Port 22/Port ${SSH_PORT}/g" /etc/ssh/sshd_config
sed -i "s/Port 22/Port ${SSH_PORT}/g" /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
# Ensure service directory exists for Fail2Ban checks
mkdir -p /var/run/sshd

# 5. Network & Firewall
echo "[5/7] Configuring UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp
ufw allow ${DERP_PORT}/tcp
ufw allow ${DERP_STUN_PORT}/udp
# Allow Docker container traffic
ufw route allow in on ${DOCKER_NET} out on any
ufw allow in on any out on ${DOCKER_NET}
# Loopback
ufw allow from 127.0.0.1
# Enable
# ufw --force enable # Commented out to prevent lockout during script run, user must enable manually or verify first

# 6. Performance & Tools
echo "[6/7] Tuning Performance..."
# Swap
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# BBR
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
fi

# Lazydocker
if ! command -v lazydocker &> /dev/null; then
    curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
fi

# 7. Fail2Ban
echo "[7/7] Configuring Fail2Ban..."
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
EOF
systemctl restart fail2ban

# Create Data Directories
echo "Creating Directories at ${DOCKER_ROOT}..."
mkdir -p ${DOCKER_ROOT}/global/certs
mkdir -p ${DOCKER_ROOT}/stable/new-api
mkdir -p ${DOCKER_ROOT}/stable/uptime-kuma
chown -R ${ADMIN_USER}:${ADMIN_USER} ${DOCKER_ROOT}

echo "=== Initialization Complete ==="
echo "Please set ADMIN_PASS for '${ADMIN_USER}' manually if needed."
echo "Don't forget to: ufw enable"
echo "Restart SSH service manually after verifying config: systemctl restart sshd"
