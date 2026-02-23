# VPS-OPS 全面重构：操作交接手册

## 代码改动汇总

| 文件 | 类型 | 核心变化 |
|------|------|---------|
| [config/fastapi-gateway/auth.py](file:///d:/work/vps-ops/config/fastapi-gateway/auth.py) | 新建 | `/ops/*` Token 鉴权模块 |
| [config/fastapi-gateway/schemas.py](file:///d:/work/vps-ops/config/fastapi-gateway/schemas.py) | 新建 | 量化/科研 Pydantic 数据模型 |
| [config/fastapi-gateway/main.py](file:///d:/work/vps-ops/config/fastapi-gateway/main.py) | 重写 | 流式代理修复 + `/ops/` 路由 |
| [config/fastapi-gateway/Dockerfile](file:///d:/work/vps-ops/config/fastapi-gateway/Dockerfile) | 修改 | `COPY . .` 修复新文件丢失问题 |
| [compose/docker-compose.yml](file:///d:/work/vps-ops/compose/docker-compose.yml) | 修改 | 新增 Vaultwarden + Kopia 高频策略 |
| [scripts/backup_vault.sh](file:///d:/work/vps-ops/scripts/backup_vault.sh) | 新建 | SQLite 热备份 + Kopia vault 快照 |

---

## 第一步：更新 `.env` 文件（必须先做）

在部署前，往 `/opt/vps-dmz/.env` 追加以下变量：

```bash
# 原有的 FASTAPI_SECRET_KEY 可以删除，不再使用

# FastAPI /ops/* 路由鉴权 Token（自己生成一个随机字符串）
VPS_TOKEN=换成你自己生成的随机字符串

# Vaultwarden 后台管理 Token（在 VPS 上运行此命令生成）
# openssl rand -base64 48
VW_ADMIN_TOKEN=换成你自己生成的随机字符串
```

> **生成随机 Token 命令**（SSH 进 VPS 执行）：
> ```bash
> openssl rand -base64 48
> ```
> 运行两次，分别填入 `VPS_TOKEN` 和 `VW_ADMIN_TOKEN`。

---

## 第二步：重新部署 FastAPI 网关

```bash
# 必须 --build 重新构建镜像（有新文件加入）
docker compose -f /opt/vps-dmz/compose/docker-compose.yml up -d --build fastapi-gateway
```

**验证 SSE 流式是否生效（从本地终端）：**
```bash
curl -N -H "Authorization: Bearer 你的AI-key" \
     https://api.660415.xyz/v1/chat/completions \
     -d '{"model":"gpt-4","messages":[{"role":"user","content":"hi"}],"stream":true}'
# 应该看到 data: {...} 逐行流出，而不是等待后一次性返回
```

**验证 /ops/ 鉴权：**
```bash
# 无 Token → 应返回 422（缺少 header）
curl -X GET https://api.660415.xyz/ops/health

# 有正确 Token → 应返回 {"status":"ok"}
curl -X GET -H "x-vps-token: 你的VPS_TOKEN" https://api.660415.xyz/ops/health
```

---

## 第三步：启动 Vaultwarden

```bash
docker compose -f /opt/vps-dmz/compose/docker-compose.yml up -d vaultwarden

# 查看启动日志
docker logs vaultwarden --tail 30
```

---

## 第四步：配置 UFW 防火墙（Tailscale 直连通道）

```bash
# 只允许 Tailscale 网卡上的流量访问 8080 端口
sudo ufw allow in on tailscale0 to any port 8080
sudo ufw status  # 确认规则生效
```

> 这样外网无法直接访问 8080，只有连上 Tailscale 后才能访问。  
> 极端情况 Cloudflare 宕机时：打开 Tailscale → 访问 `http://<VPS-Tailscale-IP>:8080`

---

## 第五步：Cloudflare 控制台操作

### 5.1 CF Tunnel — 打通 pw.660415.xyz

1. 进入 **Zero Trust → Networks → Tunnels**
2. 编辑你的 Tunnel → **Public Hostnames → Add a public hostname**
3. 填写：
   - Subdomain: `pw`
   - Domain: `660415.xyz`
   - Service: `http://vaultwarden:80`
4. 保存

### 5.2 CF Access — 保护 /admin 路径

1. 进入 **Zero Trust → Access → Applications → Add an application**
2. 选择 **Self-hosted**
3. 填写：
   - Application name: `Vaultwarden Admin`
   - Application domain: `pw.660415.xyz`
   - **Path（路径）**: `admin`  ← 关键！只保护 /admin，不影响日常同步
4. 点击 **Next → 创建 Policy**：
   - Policy name: `仅我本人`
   - Action: `Allow`
   - Rule: `Emails` → 填你的邮箱
5. 保存完成

> 效果：日常手机 App 同步毫无感知；访问 `pw.660415.xyz/admin` 时，CF 弹出 OTP 验证。

### 5.3 CF WAF — 速率限制防爆破

1. 进入 **CF 主控制台 → 你的站点 → Security → WAF → Rate limiting rules → Create rule**
2. 配置：
   - Rule name: `Vaultwarden 防密码爆破`
   - If incoming requests match: 选择 `Edit expression` 并填入：
     `(http.host eq "pw.660415.xyz" and http.request.uri.path contains "/api/accounts/prelogin")`
   - Requests: `5` requests per `10 seconds`
   - Action: `Block` for `10 seconds` (受限于免费版额度，只能选 10s，但也足够拖慢爆破脚本了)
3. 保存并启用

---

## 第六步：Vault 投产封印流程（重要！）

1. **抢占主账号**：访问 `https://pw.660415.xyz` → 注册你的账号
2. **升级 KDF**：登录后 → 设置 → 安全 → 密钥 → 将算法改为 `Argon2id`（内存 64MB，迭代 3 次）
3. **焊死大门**：SSH 进 VPS，修改 `.env`：
   ```bash
   # 把这一行
   SIGNUPS_ALLOWED=true
   # 改成
   SIGNUPS_ALLOWED=false
   ```
   然后重启：
   ```bash
   docker compose -f /opt/vps-dmz/compose/docker-compose.yml up -d vaultwarden
   ```
4. **验证后台可进**：访问 `https://pw.660415.xyz/admin`，通过 CF 邮箱 OTP 验证后，输入 `VW_ADMIN_TOKEN` 进入后台

---

## 第七步：配置 Kopia 备份 Crontab

SSH 进 VPS：

```bash
# 编辑宿主机 crontab
crontab -e
```

追加以下两行：
```cron
# 每天凌晨 2 点：全量 VPS 数据备份
0 2 * * * docker exec kopia kopia snapshot create /source >> /opt/vps-dmz/logs/backup_all.log 2>&1

# 每 6 小时：Vaultwarden 专属热备份（SQLite 热备份 + Kopia 快照）
0 */6 * * * /opt/vps-dmz/scripts/backup_vault.sh >> /opt/vps-dmz/logs/backup_vault.log 2>&1
```

保存后，手动测试一次确认脚本正常：
```bash
chmod +x /opt/vps-dmz/scripts/backup_vault.sh
/opt/vps-dmz/scripts/backup_vault.sh
```

---

## 第八步：验证备份与恢复演练

```bash
# 查看 vault 快照列表
docker exec kopia kopia snapshot list /source/vaultwarden

# 验证恢复（恢复到临时目录，不覆盖生产数据）
docker exec kopia kopia restore <snapshot-id> /tmp/restore_test

# 查看恢复出来的文件
ls -la /tmp/restore_test/
# 应该看到 db.sqlite3、db.backup.sqlite3、attachments/ 等
```

---

## 迁移 Vault 到新机器（备忘）

1. 找到最近的 vault 快照 ID：`docker exec kopia kopia snapshot list /source/vaultwarden`
2. 恢复到临时目录：`docker exec kopia kopia restore <id> /tmp/vault_export`
3. 拷出 `db.backup.sqlite3`（这是无 WAL 依赖的干净单文件）
4. 在新机器上将其 rename 为 `db.sqlite3`，放入新机器的 `/data/vaultwarden/` 目录
5. 启动新机器的 vaultwarden 容器，所有密码数据完整恢复

---

## 后续 /ops/ 路由使用说明（本地脚本调用示例）

```python
import requests

# 发送量化信号
headers = {"x-vps-token": "你的VPS_TOKEN", "Content-Type": "application/json"}
payload = {
    "symbol": "sh000001",
    "signal_type": "buy",
    "strategy_name": "MA20_Cross",
    "price": 3200.5
}
r = requests.post("https://api.660415.xyz/ops/quant/signal", headers=headers, json=payload)
print(r.json())  # {"status": "success", ...}
```

---

## 第九步：安装 Nginx 日志轮转（防爆盘必须做）

nginx-relay 的 access.log 写入的是宿主机目录（volume 挂载），Docker 的 logging 限制管不到它。不配 logrotate 的话，几年后可能积累几 GB。

```bash
# 将 logrotate 配置文件拷贝到系统目录
cp /opt/vps-dmz/presets/logrotate-nginx.conf /etc/logrotate.d/vps-nginx

# 手动运行一次验证配置正确
logrotate -d /etc/logrotate.d/vps-nginx   # -d 是试运行，不真实操作
logrotate /etc/logrotate.d/vps-nginx       # 真实执行一次
```

> 系统会自动每有个 logrotate 任务，每天轮转一次，保留 7 天，并自动 gzip 压缩。

---

## 磁盘占用快速排查命令

```bash
# 查看 Docker 日志占盘情况（/var/lib/docker/containers/）
docker system df -v

# 查看数据目录占盘
du -sh /opt/vps-dmz/data/* | sort -hr

# 查看日志目录
du -sh /opt/vps-dmz/logs/* | sort -hr

# 清理 Docker 无用资源（镜像等）
docker system prune -f
```
