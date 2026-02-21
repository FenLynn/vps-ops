# 🚦 VPS-OPS v2.0 — 全平台部署检查清单

> 适用场景：全新 VPS，WebDAV 也是空的，从零开始测试每一个模块。
> 当前证书状态：本周 5 次配额已用完，需用测试模式。

---

## 📋 总览：需要在哪些平台做什么

| 平台 | 操作 | 影响模块 |
|:---|:---|:---|
| **Cloudflare (域名侧)** | 创建 Tunnel + 配置路由 | 所有通过隧道访问的服务 |
| **Cloudflare (Zero Trust)** | 配置 Access 保护 | dockge, homarr |
| **Cloudflare (WAF)** | 防盗刷规则 | music-api |
| **GitHub (仓库 Secrets)** | 添加 SSH 部署密钥 | deploy.yml CI/CD |
| **坚果云 (WebDAV)** | 创建目录 + 应用密码 | kopia 备份 |
| **Tailscale** | VPS 接入 + 关闭 Key Expiry | derper, nginx-relay |
| **VPS 本机** | 运行 init_host.sh | 所有服务 |

---

## 🖥️ 第一步：VPS 本机配置

### 1.1 必填的 `.env` 变量（在 init_host.sh 运行前必须填好）

```bash
cp .env.example .env
nano .env
```

以下变量 **不填则脚本会直接报错退出**（带 `:?` 强制校验）：

| 变量 | 示例值 | 获取方式 |
|:---|:---|:---|
| `CF_TOKEN` | `eyJh...` | Cloudflare Zero Trust → Tunnels → 创建隧道 → 复制 Token |
| `CF_DNS_API_TOKEN` | `abc123...` | Cloudflare → API Tokens → Edit zone DNS 模板 |
| `KOPIA_PASSWORD` | 任意强密码 | 自己设定，切记不要丢！ |
| `DERP_DOMAIN` | `derp.660415.xyz` | 确保已在 CF 托管该域名 |

以下变量填默认值即可先运行：

| 变量 | 推荐测试默认值 | 说明 |
|:---|:---|:---|
| `ACME_STAGING` | `true` ← **重要！** | 本周配额用完，必须设为 true |
| `NEW_API_ADMIN_PASSWORD` | 随便设一个 | New API 的 root 密码 |
| `BASE_DIR` | `/opt/vps-dmz` | 保持默认 |
| `WEBDAV_URL` | 暂时留空 | 坚果云配置好再填 |
| `WEBDAV_USER` / `WEBDAV_PASS` | 暂时留空 | 坚果云配置好再填 |
| `NAS_TAILSCALE_IP` | 暂时留空 | Tailscale 配好再填 |
| `MUSIC_API_IMAGE` | 默认值 | 默认: `binaryify/netease_cloud_music_api:latest` |
| `UNBLOCK_NETEASE_IMAGE` | 默认值 | 默认: `pan93412/unblock-netease-cloud-music:enhanced` |

> ⚠️ **测试阶段的关键提醒**：
> `ACME_STAGING=true` 时，`derper` 拿到的是测试证书，DERP 功能可以正常测连通性，但 Tailscale 客户端可能会报"证书不受信任"的警告（不影响 DERP 本身中继功能）。正式上线前把 `ACME_STAGING=false`，然后删掉 `data/acme/` 目录并重新运行 `docker compose up -d`。

### 1.2 运行初始化脚本

```bash
sudo bash scripts/init_host.sh
```

### 1.3 验证服务全部启动

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
```

期望结果（全部 `Up`）：

| 容器名 | 预期状态 | 无 WebDAV 时 |
|:---|:---|:---|
| `cloudflared` | ✅ `Up` | 正常（需要 CF_TOKEN） |
| `acme` | ✅ `Up (daemon)` | 正常 |
| `acme-init` | ✅ `Exited (0)` | 正常（一次性任务） |
| `watchtower` | ✅ `Up` | 正常 |
| `derper` | ✅ `Up` | 依赖 acme-init 成功 |
| `new-api` | ✅ `Up (healthy)` | 正常 |
| `unblock-netease` | ✅ `Up` | 正常 |
| `music-api` | ✅ `Up` | 正常 |
| `nginx-relay` | ✅ `Up` | 正常（NAS 不通时请求会 502） |
| `fastapi-gateway` | ✅ `Up` | 需先构建镜像 |
| `uptime-kuma` | ✅ `Up (healthy)` | 正常 |
| `kopia` | ⚠️ `Up` 但无法连接仓库 | **WebDAV 为空时会报错，但容器不退出** |
| `dockge` | ✅ `Up` | 正常 |
| `homarr` | ✅ `Up` | 正常 |

---

## ☁️ 第二步：Cloudflare 配置

### 2.1 在哪里操作
- **Zero Trust**：[https://one.dash.cloudflare.com/](https://one.dash.cloudflare.com/)
- **WAF / DNS**：[https://dash.cloudflare.com/](https://dash.cloudflare.com/) → 选域名 `660415.xyz`

### 2.2 获取 Tunnel Token (`CF_TOKEN`)

1. Zero Trust → Networks → Tunnels → **Create a tunnel**
2. 名称随意（如 `vps-ops`）
3. 选 **Docker** 环境
4. 复制命令中 `--token` 后的字符串 → 填入 `.env` 的 `CF_TOKEN`

### 2.3 配置 Public Hostnames（Tunnel 路由）

Zero Trust → Networks → Tunnels → 选你的 Tunnel → **Public Hostnames** → Add

| Hostname | Service | 测试时是否需要 |
|:---|:---|:---|
| `new-api.660415.xyz` | `http://new-api:3000` | ✅ 优先配置 |
| `api.660415.xyz` | `http://fastapi-gateway:8000` | ✅ 优先配置 |
| `status.660415.xyz` | `http://uptime-kuma:3001` | ✅ 优先配置 |
| `music-api.660415.xyz` | `http://music-api:3000` | 🟡 后续 |
| `webhook.660415.xyz` | `http://nginx-relay:80` | 🟡 Tailscale 配好后 |
| `dockge.660415.xyz` | `http://dockge:5001` | ✅ 优先配置 |
| `home.660415.xyz` | `http://homarr:7575` | 🟡 后续 |

### 2.4 Access 保护（可选，生产前记得加）

Zero Trust → Access → Applications → Add

- 保护 `dockge.660415.xyz` 和 `home.660415.xyz`
- 策略：Email OTP（填你的邮箱）

### 2.5 获取 DNS API Token (`CF_DNS_API_TOKEN`)

1. [https://dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
2. **Create Token** → 使用 **Edit zone DNS** 模板
3. Zone Resources → Include → Specific zone → `660415.xyz`
4. 复制 Token → 填入 `.env` 的 `CF_DNS_API_TOKEN`

### 2.6 WAF 防盗刷（等 music 服务稳定后再配）

域名 `660415.xyz` → Security → WAF → Custom rules → Create rule：

```
(http.host eq "music-api.660415.xyz") and (not http.referer contains "music.660415.xyz")
→ Block
```

---

## 🔑 第三步：GitHub Secrets 配置

> 如果不需要 CI/CD 自动部署（手动 SSH 部署），此步可以跳过。

仓库 → Settings → Secrets and variables → Actions → **New repository secret**

| Secret 名称 | 值 | 获取方式 |
|:---|:---|:---|
| `VPS_HOST` | VPS 公网 IP | 你的 VPS 控制台 |
| `VPS_SSH_PORT` | `22222` | config.ini 中的 SSH_PORT |
| `VPS_USER` | `sudor` | config.ini 中的 ADMIN_USER |
| `VPS_SSH_KEY` | SSH 私钥内容 | 本机 `cat ~/.ssh/id_rsa` |

---

## 🌐 第四步：Tailscale 配置

> 影响模块：`derper` (DERP 中继) + `nginx-relay` (NAS webhook)

### 4.1 VPS 上安装 Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey=${TAILSCALE_AUTH_KEY}
tailscale status  # 确认 VPS 和 NAS 都显示 Connected
```

### 4.2 Tailscale 后台配置

1. 登录 [https://login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)
2. 找到 VPS 节点 → 三点菜单 → **Disable key expiry**（永不过期）
3. 记下 NAS 的 Tailscale IP（`100.x.x.x`）→ 填入 `.env` 的 `NAS_TAILSCALE_IP`

### 4.3 nginx-relay 的额外说明

`nginx.conf` 中 `host.docker.internal` 需要 Docker 支持，在 **Linux 上默认不自动解析**。需要在 compose 中为 `nginx-relay` 添加 extra_hosts，或直接用 NAS 的 Tailscale IP 替换。

**临时解决方案**（待后续修复）：把 `nginx.conf` 里的 `host.docker.internal` 改为 `${NAS_TAILSCALE_IP}`。

---

## 💾 第五步：坚果云 WebDAV 配置

> 影响模块：`kopia` 备份。WebDAV 未配置时 Kopia 会报错，但其他服务不受影响。

1. 登录 [https://www.jianguoyun.com/](https://www.jianguoyun.com/)
2. 账户信息 → 安全选项 → **第三方应用管理** → 添加应用密码
   - 应用名称：`vps-kopia`
   - 生成应用密码（不是登录密码！）
3. 在坚果云根目录新建文件夹：`vps-dmz-kopia`
4. 填入 `.env`：
   ```ini
   WEBDAV_URL=https://dav.jianguoyun.com/dav/vps-dmz-kopia
   WEBDAV_USER=你的注册邮箱
   WEBDAV_PASS=刚才生成的应用密码
   ```
5. 填完后重启 kopia：`docker restart kopia`

---

## 🧪 模块测试顺序建议

以下是从零开始的最优测试顺序（避免阻塞）：

```
阶段1: 验证基础网络
  → cloudflared 运行 + Cloudflare Tunnel 路由配置
  → 访问 https://status.660415.xyz (uptime-kuma)
  → 访问 https://dockge.660415.xyz (dockge)

阶段2: 验证核心业务
  → 访问 https://new-api.660415.xyz (AI 接口管理)
  → 访问 https://api.660415.xyz (FastAPI 网关状态页)

阶段3: 验证 DERP + 证书
  → docker logs acme-init → 确认看到 "letsencrypt_test" 字样
  → derp 能正常监听 33445 端口 (telnet VPS_IP 33445)

阶段4: 配置坚果云 WebDAV + Kopia
  → docker logs kopia → 应看到 "Kopia 就绪"

阶段5: 配置 Tailscale + nginx-relay
  → tailscale status 确认连通
  → curl https://webhook.660415.xyz/health

阶段6: 验证音乐服务
  → curl https://music-api.660415.xyz/search?keywords=test

阶段7: 正式上线
  → 修改 .env: ACME_STAGING=false
  → 删除 data/acme/ 目录: rm -rf /opt/vps-dmz/data/acme/*
  → 重启证书相关服务: docker compose up -d acme acme-init derper
```

---

## ⚡ 快速参考：文件位置速查

| 操作 | 命令 |
|:---|:---|
| 查看 .env 当前值 | `cat /opt/vps-dmz/.env` |
| 修改 .env | `nano /opt/vps-dmz/.env` |
| 查看所有容器状态 | `docker ps` |
| 查看某容器日志 | `docker logs -f --tail 50 <容器名>` |
| 切换到生产证书 | 改 `ACME_STAGING=false` → `rm -rf /opt/vps-dmz/data/acme/*` → `docker compose up -d` |
| 手动触发备份 | `bash /opt/vps-dmz/scripts/backup_kopia.sh` |
| 重新部署所有服务 | `cd /opt/vps-dmz && docker compose up -d` |
