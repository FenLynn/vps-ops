#!/bin/bash
# =============================================================================
# VPS-OPS — SSH 加固脚本 (安全沙盒：先预览，后执行，随时回退)
#
# 职责:
#   - 修改 SSH 端口、禁 root 登录、禁密码认证、纯公钥模式
#   - 更新 UFW/Fail2Ban 匹配新端口
#   - 激活 Tailscale 并加入 Tailnet
#
# 用法:
#   sudo -E bash ssh_harden.sh --dry-run   # 预览模式: 只打印将要执行的操作，不改任何文件
#   sudo -E bash ssh_harden.sh             # 执行模式: 自动备份并执行所有加固
#   sudo -E bash ssh_harden.sh --rollback  # 回退模式: 从最近备份恢复 sshd_config
#
# ⚠️  在新终端窗口验证 SSH 连接成功前，请勿关闭当前 SSH 会话！
# =============================================================================

set -uo pipefail

# ─── 配置区 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 加载 config.ini 获取 SSH_PORT 等配置
if [ -f "${PROJECT_DIR}/config.ini" ]; then
    source "${PROJECT_DIR}/config.ini"
fi
# 加载 .env（可能有 TAILSCALE_AUTH_KEY）
if [ -f "${PROJECT_DIR}/.env" ]; then
    export $(grep -v '^#' "${PROJECT_DIR}/.env" | grep -v '^$' | xargs) 2>/dev/null || true
fi
if [ -f "/opt/vps-dmz/.env" ]; then
    export $(grep -v '^#' "/opt/vps-dmz/.env" | grep -v '^$' | xargs) 2>/dev/null || true
fi

TARGET_PORT="${SSH_PORT:-22222}"
ADMIN_USER="${ADMIN_USER:-sudor}"
SSHD_CONFIG="/etc/ssh/sshd_config"
DROPIN_FILE="/etc/ssh/sshd_config.d/99-vps-ops.conf"
BACKUP_DIR="/etc/ssh/backups"

# ─── 参数解析 ─────────────────────────────────────────────────────────────────
MODE="execute"
for arg in "$@"; do
    case "$arg" in
        --dry-run)   MODE="dry-run" ;;
        --rollback)  MODE="rollback" ;;
        --help|-h)
            echo "用法:"
            echo "  $0 [--dry-run]   # 预览所有将要执行的操作"
            echo "  $0               # 执行 SSH 加固"
            echo "  $0 [--rollback]  # 从备份恢复 sshd_config"
            exit 0
            ;;
    esac
done

# ─── 工具函数 ─────────────────────────────────────────────────────────────────

# 在 dry-run 模式下只打印，否则实际执行
dryrun_or_exec() {
    if [ "$MODE" = "dry-run" ]; then
        echo "    [DRY-RUN] $*"
    else
        eval "$@"
    fi
}

disable_ssh_socket() {
    if systemctl is-active ssh.socket &>/dev/null || \
       systemctl is-enabled ssh.socket 2>/dev/null | grep -q "enabled"; then
        dryrun_or_exec "systemctl disable --now ssh.socket 2>/dev/null || true"
    fi
    dryrun_or_exec "systemctl mask ssh.socket 2>/dev/null || true"
    dryrun_or_exec "systemctl enable ssh.service 2>/dev/null || true"
}

# ─── ROOT 检查 ────────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 需要 root 权限运行。请使用: sudo -E bash $0 $*"
    exit 1
fi

echo "=============================================================="
echo "  VPS-OPS SSH 加固脚本  [MODE: ${MODE^^}]"
echo "  目标端口: ${TARGET_PORT}  管理用户: ${ADMIN_USER}"
echo "=============================================================="
echo ""

# =============================================================================
# 回退模式
# =============================================================================
if [ "$MODE" = "rollback" ]; then
    echo "🔄 [ROLLBACK] 正在从备份恢复 sshd_config..."

    # 找到最近的备份
    LATEST_BAK=$(ls -t "${BACKUP_DIR}"/sshd_config.bak.* 2>/dev/null | head -1)
    if [ -z "$LATEST_BAK" ]; then
        echo "❌ 未找到备份文件 (${BACKUP_DIR}/sshd_config.bak.*)"
        echo "   如果从未执行过加固，则无需回退。"
        exit 1
    fi

    echo "  📂 找到备份: $LATEST_BAK"

    # 恢复主配置
    cp "$LATEST_BAK" "$SSHD_CONFIG"
    echo "  ✅ 已恢复: $SSHD_CONFIG"

    # 删除 Drop-in
    if [ -f "$DROPIN_FILE" ]; then
        rm -f "$DROPIN_FILE"
        echo "  ✅ 已删除 Drop-in: $DROPIN_FILE"
    fi

    # 恢复 UFW 规则 (放行 22，关闭自定义端口)
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 22/tcp comment 'SSH-Rollback' >/dev/null 2>&1 || true
        ufw delete allow "${TARGET_PORT}/tcp" >/dev/null 2>&1 || true
        ufw reload >/dev/null 2>&1 || true
        echo "  ✅ UFW 已恢复: 放行 22，关闭 ${TARGET_PORT}"
    fi

    # 恢复 Fail2Ban
    if [ -f /etc/fail2ban/jail.local ]; then
        sed -i "s/^port.*/port     = 22/" /etc/fail2ban/jail.local 2>/dev/null || true
        systemctl restart fail2ban 2>/dev/null || true
        echo "  ✅ Fail2Ban 已恢复: 仅监听 22"
    fi

    # 重启 SSH
    disable_ssh_socket
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart ssh.service 2>/dev/null || service ssh restart
    fi

    echo ""
    echo "  ✅ 回退完成，SSH 已恢复到端口 22 (root/密码认证均已恢复)"
    echo "  🔍 验证: ss -tulpn | grep sshd"
    exit 0
fi

# =============================================================================
# 预览模式 / 执行模式
# =============================================================================

# ─── 前置安全检查 ─────────────────────────────────────────────────────────────

# 检查 sudor 用户是否有公钥（防止禁密码后锁死）
AUTH_KEYS="/home/${ADMIN_USER}/.ssh/authorized_keys"
KEY_OK=false
if [ -f "$AUTH_KEYS" ] && [ -s "$AUTH_KEYS" ]; then
    KEY_OK=true
fi
# root 也可以
if [ -f /root/.ssh/authorized_keys ] && [ -s /root/.ssh/authorized_keys ]; then
    KEY_OK=true
fi

if [ "$KEY_OK" = false ]; then
    echo "❌ 安全阻断: 未在 ${AUTH_KEYS} 或 /root/.ssh/authorized_keys 找到任何公钥！"
    echo "   禁用密码认证后将无法登录，已中止。"
    echo "   请先将你的 SSH 公钥写入 authorized_keys，再执行本脚本。"
    exit 1
fi
echo "  ✅ 公钥检查通过 (${AUTH_KEYS} 已有内容)"

# 检查目标端口是否已开放
if command -v ufw >/dev/null 2>&1; then
    UFW_STATUS=$(ufw status 2>/dev/null)
    if ! echo "$UFW_STATUS" | grep -q "${TARGET_PORT}/tcp"; then
        echo "  ⚠️  UFW 中端口 ${TARGET_PORT} 尚未开放（脚本会自动添加）"
    fi
fi

echo ""
echo "─── 将要执行的操作 ───────────────────────────────────────────"
echo ""

# ─── Step 1: 备份 sshd_config ─────────────────────────────────────────────
BAK_FILE="${BACKUP_DIR}/sshd_config.bak.$(date +%Y%m%d_%H%M%S)"
echo "📋 Step 1: 备份 sshd_config"
echo "    备份路径: ${BAK_FILE}"
dryrun_or_exec "mkdir -p '${BACKUP_DIR}'"
dryrun_or_exec "cp '${SSHD_CONFIG}' '${BAK_FILE}'"

# ─── Step 2: 写入 SSH 加固 Drop-in ───────────────────────────────────────
echo ""
echo "📋 Step 2: 写入 SSH 加固配置 (Drop-in)"
echo "    文件: ${DROPIN_FILE}"
echo "    内容:"
echo "      Port ${TARGET_PORT}"
echo "      PermitRootLogin no"
echo "      PasswordAuthentication no"
echo "      PubkeyAuthentication yes"

if [ "$MODE" = "execute" ]; then
    mkdir -p /etc/ssh/sshd_config.d
    cat > "${DROPIN_FILE}" << EOF
# SSH 加固配置 (由 vps-ops ssh_harden.sh 写入于 $(date))
# 回退: sudo -E bash /opt/vps-dmz/scripts/ssh_harden.sh --rollback
Port ${TARGET_PORT}
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
X11Forwarding no
EOF
    # 清理主配置中可能存在的冲突行（由 init_host.sh 写入的 yes 值）
    sed -i 's/^PermitRootLogin yes/# PermitRootLogin yes  # ← disabled by ssh_harden.sh/' \
        "${SSHD_CONFIG}" 2>/dev/null || true
    sed -i 's/^PasswordAuthentication yes/# PasswordAuthentication yes  # ← disabled by ssh_harden.sh/' \
        "${SSHD_CONFIG}" 2>/dev/null || true
fi

# ─── Step 3: UFW 更新 ─────────────────────────────────────────────────────
echo ""
echo "📋 Step 3: 更新 UFW 防火墙"
echo "    放行: ${TARGET_PORT}/tcp"
echo "    移除: 22/tcp (在新端口验证成功之后才移除，防止锁死)"
if command -v ufw >/dev/null 2>&1; then
    dryrun_or_exec "ufw allow '${TARGET_PORT}/tcp' comment 'SSH-Hardened' >/dev/null"
    dryrun_or_exec "ufw reload >/dev/null"
fi

# ─── Step 4: 更新 Fail2Ban ────────────────────────────────────────────────
echo ""
echo "📋 Step 4: 更新 Fail2Ban 规则"
echo "    端口: 22,${TARGET_PORT} (过渡期双监听)"

# 尝试获取当前登录的客户端 IP，加入白名单防误伤自己
CURRENT_CLIENT_IP=""
if [ -n "${SSH_CLIENT:-}" ]; then
    CURRENT_CLIENT_IP=$(echo "$SSH_CLIENT" | awk '{print $1}')
fi

if [ -f /etc/fail2ban/jail.local ]; then
    dryrun_or_exec "sed -i 's/^port.*/port     = 22,${TARGET_PORT}/' /etc/fail2ban/jail.local"

    if [ -n "$CURRENT_CLIENT_IP" ]; then
        echo "    发现当前客户端 IP: ${CURRENT_CLIENT_IP}，加入 ignoreip 白名单"
        # 强制检查并追加 ignoreip
        if grep -q "^ignoreip" /etc/fail2ban/jail.local; then
            if ! grep -q "${CURRENT_CLIENT_IP}" /etc/fail2ban/jail.local; then
                dryrun_or_exec "sed -i 's/^ignoreip.*/& ${CURRENT_CLIENT_IP}/' /etc/fail2ban/jail.local"
            fi
        else
            dryrun_or_exec "sed -i '/\[sshd\]/a ignoreip = 127.0.0.1/8 ::1 ${CURRENT_CLIENT_IP}' /etc/fail2ban/jail.local"
        fi
    fi

    # 不管 fail2ban 之前是不是死的，强行拉起来
    dryrun_or_exec "systemctl restart fail2ban 2>/dev/null || true"
fi

# ─── Step 5: 禁用 ssh.socket + 重启 SSH ──────────────────────────────────
echo ""
echo "📋 Step 5: 重启 SSH 服务 (使配置生效)"
echo "    - mask ssh.socket (Ubuntu 24.04+ 防劫持)"
echo "    - systemctl restart ssh.service"
disable_ssh_socket
dryrun_or_exec "systemctl restart ssh.service 2>/dev/null || service ssh restart"

# ─── Step 6: 验证新端口监听 ────────────────────────────────────────────────
echo ""
echo "📋 Step 6: 验证新端口监听"
if [ "$MODE" = "execute" ]; then
    sleep 2
    if ss -tulpn 2>/dev/null | grep -q ":${TARGET_PORT}"; then
        echo "  ✅ SSH 已成功监听在端口 ${TARGET_PORT}"
    else
        echo "  ❌ 严重告警: 端口 ${TARGET_PORT} 未被监听！"
        echo ""
        echo "  🔄 正在自动尝试回退..."
        "$0" --rollback
        echo "  请通过 VNC 排查 ssh.socket 状态后重试。"
        exit 1
    fi
else
    echo "    [DRY-RUN] 验证端口 ${TARGET_PORT} 是否监听"
fi

# ─── Step 7: Tailscale 激活 ────────────────────────────────────────────────
echo ""
echo "📋 Step 7: 激活 Tailscale (普通内网穿透模式)"
if command -v tailscale >/dev/null 2>&1; then
    if [ -n "${TAILSCALE_AUTH_KEY:-}" ]; then
        echo "    检测到 TAILSCALE_AUTH_KEY，自动加入 Tailnet"
        dryrun_or_exec "tailscale up --authkey='${TAILSCALE_AUTH_KEY}' --accept-routes 2>/dev/null || true"
    else
        echo "    未检测到 TAILSCALE_AUTH_KEY，需要手动执行:"
        echo "    tailscale up --authkey=<KEY>"
    fi
else
    echo "    ⚠️  Tailscale 未安装，跳过"
fi

# ─── Step 8: Cloudflare Web SSH 说明 ──────────────────────────────────────
echo ""
echo "📋 Step 8: Cloudflare Web SSH (需在控制台手动配置)"
echo "    在 Cloudflare Zero Trust → Tunnels → Public Hostnames 添加:"
echo "    Hostname: ssh.660415.xyz"
echo "    Service:  ssh://host.docker.internal:${TARGET_PORT}"
echo "    在 Access → Applications 为 ssh.660415.xyz 创建应用并开启 Browser Rendering"

# ─── 最终提示 ──────────────────────────────────────────────────────────────
echo ""
echo "=============================================================="
if [ "$MODE" = "dry-run" ]; then
    echo "  ✅ [DRY-RUN] 以上是将要执行的全部操作"
    echo "  执行加固: sudo -E bash $0"
    echo "  回退加固: sudo -E bash $0 --rollback"
else
    echo "  ✅ SSH 加固完成！"
    echo ""
    echo "  ⚠️  重要: 请立即在新的终端窗口测试连接（不要关闭当前会话）:"
    echo "     ssh -p ${TARGET_PORT} ${ADMIN_USER}@<VPS_IP>"
    echo ""
    echo "  如果新端口连接成功，可选择移除 22 端口放行:"
    echo "     ufw delete allow 22/tcp"
    echo ""
    echo "  如需回退: sudo -E bash $0 --rollback"
fi
echo "=============================================================="
