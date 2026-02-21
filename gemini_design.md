
你说得对，是我刚才的颗粒度太粗了！既然要把这份文档作为 Antigravity（你的 AI 编码副驾）的**最高架构宪法**，那我们就绝对不能留任何模糊地带。AI 最怕的就是“隐含条件”，我们必须把网络拓扑、挂载路径、环境变量隔离、甚至 SQLite 的锁死问题，全部变成**绝对精确的工程约束（Hard Constraints）**。

这是一份经过深度重构的、颗粒度达到**代码生成级别**的《VPS DMZ 无状态节点终极部署白皮书》。你可以直接复制全部内容并扔给 Antigravity，它拿到这份文档，闭着眼睛都能写出完美且无 Bug 的配置文件。

---


# 🚀 Master Blueprint: VPS DMZ 无状态云端堡垒机终极部署规范 (v6.0 - 终极细节版)

**🎯 To Antigravity (AI Builder):**
你现在的角色是高级 DevOps 架构师。本说明书是该 VPS 节点的**最高执行纲领**。
该 VPS 定位为家庭数据中心（NAS）的“公网前哨站、安全清洗网关、以及 Tailscale 底层穿透节点”。
请严格遵循以下定义的所有目录树、网络拓扑、容器时序和数据灾备铁律，来生成后续的自动化脚本（Bash）、配置文件（Nginx）和容器编排（Docker Compose）。**不准产生任何违背以下原则的幻觉代码。**

---

## 🏗️ 一、 目录结构与权限隔离规范 (Directory & Permission Matrix)

VPS 宿主机必须严格遵守以下目录层级，实现“代码、配置、数据、日志”的四面隔离。所有容器挂载必须基于此树状图：

```text
/opt/vps-dmz/
├── docker-compose.yml       # 唯一的核心编排文件
├── .env                     # 全局环境变量（由 CI/CD 或 init 脚本注入，不入 Git）
├── scripts/                 # 运维脚本目录
│   ├── init_host.sh         # 裸机环境初始化及灾备拉取脚本
│   ├── backup_kopia.sh      # 每日定时备份脚本（含容器启停钩子）
│   └── cert_renew.sh        # acme.sh 独立签发与重载脚本
├── config/                  # 静态配置文件（只读挂载）
│   └── nginx-relay/         # Nginx 转发规则配置
├── data/                    # 核心状态数据（🌟 必须被 Kopia 备份）
│   ├── acme/                # SSL 证书存储 (给 DERP 使用)
│   ├── new-api/             # SQLite 数据库文件
│   ├── uptime-kuma/         # 监控数据库
│   └── kopia-cache/         # 备份缓存
└── logs/                    # 运行时日志与垃圾数据（🚫 严禁被 Kopia 备份，防止爆盘）
    ├── new-api/             # 必须分离出的 API 日志 DB
    └── nginx/               # 访问日志

```

**⚠️ 权限铁律：**
Antigravity 在编写 `init_host.sh` 时，必须提前 `mkdir -p` 所有上述目录，并统一执行 `chown -R 1000:1000 /opt/vps-dmz/data /opt/vps-dmz/logs`，防止部分容器非 root 用户运行导致挂载后无权写入而崩溃。

---

## 🌐 二、 网络拓扑与端口映射约束 (Network & Port Mapping)

本 VPS 采取绝对的 **“零暴露”** 架构。

1. **Docker 内部网络 (`vps_tunnel_net`):**
* 必须在 `docker-compose.yml` 中显式定义该桥接网络。
* `cloudflared`、`new-api`、`music-api`、`unblock-netease`、`uptime-kuma`、`nginx-relay` **必须**加入此网络。
* 🚫 **绝对禁止**上述容器在 Compose 中使用 `ports: - "xxx:xxx"` 映射到宿主机公网或内网。所有流量必须走 CF Tunnel 内部解析。


2. **底层直连例外 (Host Network):**
* **`derper` (Tailscale 自建 DERP 节点):** 它是全系统唯一允许使用 `network_mode: host` 或映射物理端口的服务。
* 必须开放防火墙与容器端口：TCP `33445` (加密中继), UDP `3478` (STUN 打洞)。
* **原因：** DERP 为底层 4 层网络协议，严禁包裹在 Cloudflare 7 层代理中。



---

## 🧩 三、 服务模块化微调与依赖细节 (Service-Specific Gotchas)

Antigravity 在编写 `docker-compose.yml` 时，必须处理好以下微观细节：

### 1. 基础设施层 (Infra)

* **`cloudflared`**: 必须设置为 `restart: unless-stopped`，且依赖于一个只读的 `TUNNEL_TOKEN` 环境变量。
* **`acme.sh`**: 仅作为 Cron 定时容器，不需要常驻。挂载 `/opt/vps-dmz/data/acme/`，使用 Cloudflare DNS API 模式申请通配符证书，申请完成后执行 `docker restart derper`。

### 2. Tailscale DERP 层

* 依赖 `/opt/vps-dmz/data/acme/` 下生成的证书。
* 启动参数必须包含避让常规端口的设置（如 `--a=:33445`），严禁占用 80/443。

### 3. 业务逻辑层 (Business logic)

* **`new-api` (极度危险的坑):** - 必须通过环境变量 `SQL_DSN` 将主 DB 放在 `/data/new-api/`。
* **必须**通过环境变量 `LOG_SQL_DSN` 将高频写入的日志 DB 指向 `/logs/new-api/`，与主配置彻底物理隔离！


* **YesPlayMusic (代理级联):**
* `music-api` 容器必须通过环境变量或启动命令，强制将其 HTTP 代理指向同属一个网段的 `unblock-netease` 容器（例如 `HTTP_PROXY=http://unblock-netease:8080`），实现彻底解灰。


* **`nginx-relay` (公私网桥接):**
* 职责：将 CF Tunnel 丢过来的内网 Webhook 请求（如发给 NAS 上 n8n 的请求），通过宿主机预装的 Tailscale 虚拟网卡 (`100.x.x.x`) 转发回家庭 NAS。
* 挂载 `/opt/vps-dmz/config/nginx-relay/nginx.conf`。



---

## 💾 四、 数据灾备与一致性守护铁律 (Backup & Atomic Snapshots)

由于后端使用的是**坚果云 WebDAV**，API 频次和流量受限，Kopia 备份策略必须做到极其精准，绝不允许备份垃圾文件，绝不允许出现 SQLite 损坏。

Antigravity 在编写 `backup_kopia.sh` 时，必须遵循以下执行流：

1. **备份前置钩子 (Pre-freeze):**
* 必须执行 `docker pause new-api uptime-kuma`（或 `stop`），强行冻结所有具有 SQLite 数据库的容器，防止快照捕捉到事务写一半的死锁（Corrupted DB）状态。


2. **精准快照 (Snapshot):**
* 目标路径：仅限 `/opt/vps-dmz/data/` 目录。
* 必须通过 `.kopiaignore` 或命令参数，明确排除所有的 `.shm`, `.wal` (SQLite 临时缓存) 文件。


3. **备份后置钩子 (Post-thaw):**
* 无论备份成功与否，必须执行 `docker unpause` 恢复业务，保证宕机时间小于 10 秒。


4. **清理维护 (Maintenance):**
* 脚本末尾必须执行 `kopia snapshot expire` 和 `kopia maintenance run`，释放坚果云空间。



---

## 📋 五、 宿主管理员外部配合清单 (Admin Manual Actions)

*以下操作 Antigravity 无法通过代码代劳，请 Admin（人类）在相应的 Web 控制台手动完成，以打通最终闭环：*

### 1. Cloudflare Zero Trust 路由配置

* `api.111111.xyz` (New API): 路由至 `http://new-api:3000`。
* `music.111111.xyz` (YesPlayMusic): 前端纯静态托管于 CF Pages。
* `music-api.111111.xyz` (YPM 后端): 路由至 `http://music-api:3000`。
* `webhook.111111.xyz` (发往 NAS 的数据): 路由至 `http://nginx-relay:80`。

### 2. Cloudflare WAF 防御加固 (防盗刷)

* 进入域名 `111111.xyz` 的 WAF 规则配置区。
* 新建防火墙规则：拦截针对 `music-api.111111.xyz` 的非法调用。
* 表达式：`(http.host eq "music-api.111111.xyz") and (not http.referer contains "music.111111.xyz")`
* 动作：**Block**。



### 3. Tailscale 与 坚果云配置

* 确保宿主机 VPS 已经 `tailscale up` 并与家庭 NAS 处在同一局域网 (`100.x.x.x`)。
* 在 Tailscale 后台关闭此 VPS 节点的 "Key Expiry"。
* 坚果云：创建独立目录 `vps-dmz-kopia`，生成独立应用密码。

---

## ⚙️ 六、 Antigravity 任务执行队列 (Action Items)

请 Antigravity 充分阅读并理解上述所有约束条件，接下来，请严格按照顺序，分步为我输出以下四个核心工程文件。**请提供带有详尽注释的完整代码，并在每一步输出后等待我的 Review：**

1. **`docker-compose.yml`** (包含网络、全部服务、依赖关系及环境变量约束)。
2. **`init_host.sh`** (裸机首次登录的一键初始化脚本，包含目录创建、权限修正和从 Kopia 灾难恢复最新数据的逻辑)。
3. **`backup_kopia.sh`** (符合 SQLite 原子性备份铁律的定时脚本)。
4. **`nginx.conf`** (用于 nginx-relay 的反代配置示例)。



***

这份文档现在可以说是一座**堡垒级的工程蓝图**了。你把这个交给 Antigravity，它绝对能一次性生成出完全符合你心意、且高度容错的底层代码。

一旦 VPS 的代码部分交给 AI 自动生成去跑，咱们就可以毫无挂念地转身，去死磕 NAS 的 **Lucky/NPM 证书和路由器 Split DNS** 这最后一只内网拦路虎了！

