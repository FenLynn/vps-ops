# 🚀 VPS-Ops v2.0: DMZ 无状态云端堡垒机

<div align="center">

**零基础 · 全自动 · 无需公网 IP · SQLite 原子性备份**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-compose-blue)](https://docs.docker.com/compose/)
[![Cloudflare](https://img.shields.io/badge/cloudflare-zero--trust-orange)](https://www.cloudflare.com/)

</div>

---

## 📖 这是一个什么项目？

VPS-Ops 是一个 **"基础设施即代码 (IaC)"** 的自动化部署方案。它能将一台全新的 VPS，通过一条命令，变成一个**安全、现代、功能强大**的私人云端堡垒机。

该 VPS 定位为家庭数据中心（NAS）的"公网前哨站、安全清洗网关、Tailscale 底层穿透节点"。

---

## 🏗️ 架构总览

```mermaid
graph TD
    User((用户)) --> CF[Cloudflare 全球边缘节点]
    CF --> Tunnel[🔒 安全隧道]

    subgraph VPS [VPS 服务器 /opt/vps-dmz/]
        Tunnel --> |vps_tunnel_net| Services

        subgraph Infra [基础设施层]
            ACME[acme.sh 证书管理]
            Watchtower[自动更新]
        end

        subgraph Services [业务逻辑层]
            MusicApp[YesPlayMusic: 音乐全栈 (前端+API+解灰)]
            FastAPI[fastapi-gateway: 中台与流量网关]
            NginxRelay[nginx-relay: NAS 桥接]
            Uptime[uptime-kuma: 监控面板]
        end

        subgraph Management [管理控制面]
            Dozzle[dozzle: 轻量容器日志]
            Homepage[homepage: 极客导航仪表盘]
        end

        subgraph Backup [灾备系统]
            Kopia[Kopia 增量快照引擎] --> CF_R2[☁️ Cloudflare R2 对象存储]
        end
    end

    DERP[derper: Tailscale DERP] -.->|TCP:33445 + UDP:3478| User
    NginxRelay -.->|Tailscale 100.x.x.x| NAS[🏠 家庭 NAS]
```

### 域名生态体系

| 二级域名 | 部署位置 | 服务 | 核心功能 |
|:---|:---|:---|:---|
| `api.660415.xyz` | VPS | FastAPI 网关 | 统一 API 入口（聚合 /ops 数据中台） |
| `music.660415.xyz` | VPS | YesPlayMusic | 音乐播放器（全栈同源） |
| `music-api.660415.xyz` | VPS | Music API | 音乐后端 API |
| `monitor.660415.xyz` | VPS | Uptime Kuma | 监控面板 |
| `webhook.660415.xyz` | VPS | nginx-relay | Webhook 推送穿透至内网 NAS |
| `dozzle.660415.xyz` | VPS | Dozzle | 容器全局日志 (受 Access 验证保护) |
| `home.660415.xyz` | VPS | Homepage | 导航仪表盘 (受 Access 验证保护) |
| `derp.660415.xyz` | VPS | DERP | Tailscale 中继 (TCP/UDP 直连) |

---

## 📁 目录结构

```text
vps-ops/                          # Git 仓库
├── compose/
│   └── docker-compose.yml        # 唯一核心编排文件 (14 个服务)
├── config/
│   ├── nginx-relay/nginx.conf    # Nginx 反代配置
│   └── fastapi-gateway/          # FastAPI 网关代码
├── scripts/
│   ├── init_host.sh              # 裸机一键初始化
│   ├── backup_kopia.sh           # 原子性备份
│   ├── cert_renew.sh             # 证书续期回调
│   └── prune.sh                  # Docker 清理
├── presets/                      # Shell 预设
├── .github/workflows/            # CI/CD
├── .env.example                  # 环境变量模板
└── config.ini                    # 基础配置
```

VPS 部署后的运行时目录：

```text
/opt/vps-dmz/                     # 四维隔离
├── docker-compose.yml
├── config/   → 静态配置 (只读挂载)
├── data/     → 核心数据 (Kopia 备份)
└── logs/     → 日志数据 (不备份)
```

---

## ⚡️ 初始化与全自动灾备恢复 (BDR)

本项目的 `init_host.sh` 脚本不仅仅是一个安装脚本，它是一个**具备自愈能力的开荒与云端灾备恢复引擎**。无论是拿到一台刚开机的纯净国内 VPS，还是旧机器面临云厂商跑路在异地机房浴火重生，你只需执行这一键命令。

### 0. 准备工作
1. 一台干净的 VPS：推荐 Debian 12 或 Ubuntu 24.04（支持 2 核 2G 等低配机型）。
2. 克隆代码与配置机密文件：
   ```bash
   git clone https://github.com/FenLynn/vps-ops.git /opt/vps-dmz
   cd /opt/vps-dmz
   cp .env.example .env
   # 在此处填入你的 CF_TOKEN, CF_DNS_API_TOKEN, R2 密钥 以及 TAILSCALE_KEY 等
   nano .env
   ```
3. 一键开荒与恢复：
   ```bash
   sudo bash scripts/init_host.sh
   ```

### 1. `init_host.sh` 无限细节拆解 (执行的背后发生了什么？)
执行上述命令后，脚本将全自动处理所有的“国内机器网络坑”和环境调优配置：
- **DNS 超时彻底修复**：针对国内（如阿里云）使用 `systemd-resolved` 拉取 GitHub 的解析墙壁 I/O 阻塞，脚本启动时会暴戾将 `resolv.conf` 强制换为 `223.5.5.5` 以及 `114.114.114.114`。
- **Ubuntu 24.04 (Noble) 与 DEB822 源的智能适配**：脚本内置了最新的 非交互式(`NONINTERACTIVE`) 防治弹窗阻断方案，并根据版本将 Ubuntu 源切换为阿里云。
- **Docker 强注入与多点回退**：使用 `get.docker.com --mirror Aliyun` 安装，失败则回落阿里云 apt-repo 强装。最绝的是会在 `/etc/docker/daemon.json` 里注入了一套强力抗封锁镜像 (`daocloud` / `xuanyuan` 等)，极大减少拉取卡死。
- **极度舒适的 SSH 双端口防锁与鉴权融聚**：初始化系统往往容易由于开了防火墙/改端口/变账号导致自己锁在门外失联！我们在 `sshd_config.d/99-vps-ops.conf` 注入了**宽松模式**认证（同时放行原 `22`与自定义 `SSH_PORT`），允许所有公钥全开。你的 SSH 密钥会实现“三源大汇流”（Github Actions 注入、presets 预设加载、Root 公钥继承）合并至低权的 `sudor` 角色；同时 UFW/Firewalld 会智能双头开放防火墙！
- **平民机器（2C2G）底座魔改**：直接探测环境如果不存在数据盘虚拟映射，极其狂野地用 `dd / fallocate` 强行划出 2G 的硬 Swap 给系统。并在内核层开启 TCP BBR 和 FQ 拥塞控制保证代理丝滑度。
- **Tailnet 防死结注入**：直接解析 `.env` ，在开局无感静默执行 `tailscale up --authkey`，此举极为关键！若跳过这步，后续由于 Nginx-relay 无法通过宿主机 `tailscaled.sock` 转连 NAS，整个后端会陷落。

### 2. 时光倒流：Kopia X Cloudflare R2 自动化重构 (BDR)
如果你是因为原机器被删或毁灭，此时正拿着一台连 Docker 都没有的新系统重新跑：`init_host.sh` 是有强判断分支的。
当它跑近末尾时，它会扫描硬盘，发现 `data/` 目录空空如也，此时 **"天网"级 BDR（灾后恢复）判断机制** 将被激活：
1. 脚本会临时截断主线，单独将拥有 R2 权限体系的 `kopia` 容器脱壳拉起。
2. `kopia` 使用初始化握手术语跨海连入你那无限容量、0 费用的 Cloudflare R2。
3. 容器使用 `jq` 疯狂解析 `kopia snapshot list --json` 获取云端保存的最后一次时间结点的 Snapshot ID。
4. **一瞬解冻**：发出 `kopia restore <SNAP_ID> /source` 神之命令。R2 云端里的增量历史全数流回服务器，你的数据库、UptimeKuma 面板全部重新复刻至 `/opt/vps-dmz/data/` 之下。
5. 脚本停止 `kopia` 单点模式，接轨并重新拉起 `docker compose up -d`！

**恢复完毕**：旧机器仿佛从未死去。历史监控的波形都在，各项权限的 Token 一模一样。你的家又回来了。这就是 **无状态堡垒机 + R2 并发引擎** 联手的绝对暴力美学。

---

## 🚧 重构日志与踩坑记录 (v2.0 避坑指南)

在由零散脚本向完整的 IaC（基础设施即代码）v2.0 演进过程中，我们踩过了不少坑。在这里记录这些血泪经验，防止日后重蹈覆辙。



## 🤖 GitOps 自动控制 (GitHub Actions)

本项目推荐使用 **GitOps 零接触部署**：你不需要登录 SSH，甚至可以把 VPS 密码忘掉。一切操作通过 GitHub Actions 完成。

### GitHub Secrets 配置清单 (必录)

请在仓库 `Settings -> Secrets and variables -> Actions` 中录入以下 7 个变量：

| Secret 名称 | 示例/建议值 | 说明 |
|:---|:---|:---|
| `VPS_HOST` | `1.2.3.4` | VPS 公网 IP |
| `VPS_ROOT_PASS` | `YourPass` | **仅首次初始化用**：VPS root 初始密码 |
| `VPS_SSH_PRIVATE_KEY` | `-----BEGIN...` | **钥匙**：本地生成的 SSH 私钥 |
| `VPS_SSH_PUBKEY` | `ssh-ed25519...` | **锁**：本地生成的 SSH 公钥 |
| `VPS_ENV_CONTENT` | *(全文内容)* | **配置文件**：`.env` 文件的全部内容（含注释） |
| `VPS_SSH_PORT` | `22222` | 初始化完成后的 SSH 端口 |
| `VPS_USER` | `sudor` | 初始化完成后使用的管理账号 |

> **提示**：`VPS_ENV_CONTENT` 采取的是“全文注入”方案。你直接把本地带有 `#` 编号注释、空格、甚至空行的 `.env` 内容全选复制进去即可。

---

## 🛡️ 安全特性

- **零端口暴露**: 除 DERP (TCP 33445 + UDP 3478) 和 SSH 外，所有端口关闭
- **Cloudflare Access**: 管理面板 (Dockge/Homarr) 强制邮箱 OTP 验证
- **WAF 防盗刷**: music-api 仅允许 music.660415.xyz Referer 访问
- **SSH 加固**: Fail2Ban 自动生效；禁 root / 禁密码 / 改端口需**手动执行**（见文末章节）
- **加密备份**: Kopia AES 加密后上传到 **Cloudflare R2** 对象存储（取代原坚果云）

## 💾 备份系统: 拥抱 Cloudflare R2

随着密码库(NodeWarden)迁移至 Cloudflare 边缘计算托管，VPS 已被重构为无限接近的**无状态(Stateless)网关**！
虽然只有极少量像 UptimeKuma 等低敏感数据需要留存，但我们仍保留了工业级的 SQLite 原子性备份系统，并且将后端**彻底迁至 Cloudflare R2 对象存储**。

### 为什么选择 R2？
* **零成本、高并发**：原 WebDAV（如坚果云）不但有上传频次限制，连接还极其脆弱；R2 完全兼容 AWS S3 的 API，前 10GB 更是全球免流且**没有 Egress 下行流量费**。
* **Kopia S3 API 直连**：通过初始化代码 `kopia repository connect s3 --bucket="$R2_BUCKET" --endpoint="$R2_ENDPOINT_URL" --access-key="..." --secret-access-key="..."` 实现了完全无缝的快照管理。

### SQLite 原子性备份四步曲 (通过 crontab + 独立脚本守护)
1. Pre-freeze: `docker pause` 冻结含数据库的运行态容器
2. Snapshot: 利用 R2 无并发限制，Kopia 直接对 `/data` 发起快速快照 (排除 .shm/.wal 文件)
3. Post-thaw: `docker unpause` 瞬间解冻恢复业务响应 (< 10 秒阻断)
4. Maintenance: 宿主机每日凌晨 3 点，后台清理过期快照。

---

## 🚧 完整重构日志与无限细节避坑指南 (v2.0 巨变核心)

在由零散脚本向 v2.0 的彻底 IaC 演进中，我们进行了大刀阔斧的“断舍离”——移除冗余组件，强化网络穿透层。这背后填平了大量深不可测的坑：

### 1. "混合内容 (Mixed Content)"：CF Pages 与 API 接口的跨域劫难
**初衷**：为节省 VPS 资源并加速访问，本来计划将 YesPlayMusic 前端通过 GitHub Actions 编译后纯静态托管于 Cloudflare Pages (`music.660415.xyz`)，仅后端 API 透传。
**血泪**：CF Pages 强制 HTTPS 环境，但是如果内部 Axios 未命中网关域名的精准路径，或是跨协议引用，会被浏览器 `Mixed Content` (混合内容) 无情拦截。这直接导致听歌页面白屏或 API 并发死锁。
**破局**：**回归单体同源拓扑**。我们放弃了将前端外挂在 Pages 上的方案，将 `music-web` 也塞回了 VPS 的 `vps_tunnel_net` 中，双子域名 (`music.660415.xyz` & `music-api.660415.xyz`) 直接靠拢 CF Tunnel 控制面映射，彻底抹平 SSL 与跨域之痛。

### 2. Dashboard 灾难与新生：别了，Dockge/Homarr；你好，Dozzle/Homepage
**痛楚**：原版的 Dockge 过于厚重，并在尝试修改 Compose 树时经常带来意外的目录权限覆写灾难；而 Homarr 在面对 CF Tunnel 反向代理出的 `docker.sock` 时频频卡死报错 `Missing docker`。
**新生选择与踩坑排雷**：
- 替换为极致轻量（几MB级别）零配置的 **Dozzle** 来查看全栈所有容器实时日志。
- 全面拥抱“配置即代码”颜值狂魔 —— **Homepage**。
- **神级爬坑 —— 解决 Homepage `Host Validation` 错误**：在 CF Tunnel 防御层之后，Homepage 容器内部强行验证了 Host 投递！你如果仅仅暴露了 `home.660415.xyz`，进去之后会直接 401 Unauthorized。
  - **解法**：必须要在 `docker-compose.yml` 的 homepage 环境变量中显式暴露出 `HOMEPAGE_ALLOWED_HOSTS=home.660415.xyz`，允许反向代理隧道冒充访问者！

### 3. Docker Compose 幽灵：Python-Slim 循环构建之殇
**踩坑**：在部署自建的 FastAPI 模块时发现，由于只是简单写了 `build: ./config/fastapi-gateway`，每次 `docker-compose up -d` 都在从头安装一遍 Python 依赖！
**破局**：在 `compose.yaml` 中不仅写 `build`，更要显式写对 `image: vps-ops/fastapi-gateway:latest`，同时结合 `pull_policy: build` 构建策略。更核心的是添加了极其严格的 `.dockerignore` 排除掉庞大的 `__pycache__` 甚至是本地无关环境的入侵，彻底斩断了上下文污染链。

### 4. Nginx-Relay 网络穿透神技：打通 NAS 的最后一公里
**挑战**：需要将一个公网入口 (`webhook.660415.xyz` 的 n8n Webhook 等) 安全传至被层层保护在家庭层级内网里的 NAS (Tailscale IP)。但由于运行在 Docker 隔离网桥里，这看似是不可能的穿刺。
**无限细节**：
- **`resolver 127.0.0.11` 防止内网崩落**：对于 `nginx-relay/nginx.conf` 代理转发，必须在头上指定内置 Resolver。如果依赖原生 DNS 发往 Docker，会导致容器更新 IP 重新拉起后 Nginx 陷入无限 502。
- **破除 Bridge 隔离 —— `extra_hosts` 奇效**：我们在 `compose.yml` 的 nginx-relay 块中注入了 `extra_hosts: ["host.docker.internal:host-gateway"]` 特性。
- 借由 `host.docker.internal` 逃脱了 Docker 网桥返回给 VPS 宿主机。宿主机由于自身恰好挂载了 `tailscaled.sock`，成功承接该流量，把流量丢包给了 Tailscale 虚拟网卡 `100.x.x.x`，最终实现了奇迹般的 Webhook webhook → NAS `5678` 端口透传！

### 5. FastAPI：不只是代理，这是 /ops/ 受限数据中台
**设计转变**：起初 API 网关只是做单一代理。而在移除并剥离了各种烂尾组件（废弃 New API 等）后，它承接了所有重担。
- **True Streaming（真·流传输修复）**：之前的请求会导致 AI 接口响应全部憋在服务器内存里，前端打字机效果失效。重构后，全量移向 `httpx.AsyncClient` 共享连接池架构（防止 TCP Leak），并且使用 `resp.aiter_bytes(chunk_size=8192)` 逐块喂给 `StreamingResponse` 极速出仓。
- **`/ops/` 数据中台接口诞生**：所有带 `/ops/` 特征的路由，全都必须带上 `X-VPS-Token` Header 通过 Depends() 鉴权。包含了无限细节的专属业务逻辑：
  1. `/ops/quant/signal`：接收从别处 A 股量化系统发送来的买卖点信号，由网关落地并最终调度至 Gotify 推送。
  2. `/ops/research/paper`：负责接收并归档高功率光纤激光器相关文献的元数据（Tags, title 等），这会联动触发 Cloudflare Pages 上的学术知识库重新构建编译！

### 6. NodeWarden：放弃了的挣扎，才是最美的解脱
**告别重如泰山的密码库**：最初试图强行将高敏数据 VaultWarden（依赖极复杂的 SQLite Kopia 备份以防数据损坏）托管在 VPS 上，这完全违背了我们“公网前哨不存敏数据”的安全初衷。现在完全改用基于 CF Edge Worker 和纯 SQLite(D1) 服务器无感托管的 NodeWarden 替代，整个 VPS 从此彻底轻松蜕变。





---

## 💡 GitOps 进阶 FAQ

### Q1: 关于 SSH 端口与登录策略
- **首次部署 (`bootstrap.yml`)**：`root` + 密码 + 端口 `22`（新 VPS 默认状态）。
- **初始化后**：`init_host.sh` 创建 `sudor` 用户并注入 SSH 公钥，端口/密码策略**不自动修改**，需参考文末"手动安全加固"章节完成锁定。
- **后续更新 (`deploy.yml`)**：`sudor` + SSH 私钥 + 端口 `22222`，全自动无需密码。

### Q2: `.env` 内容可以带注释吗？
**完全可以。** 
`VPS_ENV_CONTENT` 是采取的“全文注入”方案。你直接把本地带有 `#` 注释、空格、甚至空行的 `.env` 内容全选复制进去即可。脚本会原封不动地在 VPS 上生成对应的文件。

### Q3: 想增加新服务（如 Jellyfin）怎么办？
1. 在本地修改 `compose/docker-compose.yml`，增加 Jellyfin 容器配置。
2. (可选) 如果有新密钥，更新到 GitHub 的 `VPS_ENV_CONTENT` Secret 中。
3. `git commit` & `git push`。
4. GitHub Actions 会自动触发 `deploy.yml`，在 VPS 上执行 `docker compose up -d`，新服务即刻上线。

### Q4: 想要同时管理多台 VPS 怎么办？
本方案具有极强的可横向扩展性，详见下方 **多机器管理** 章节。

---

## 🌐 扩展方案：多机器管理 (Environments)

如果你有多台 VPS（如香港节点、美国节点），可以使用 GitHub 的 **Environments** 功能进行隔离管理：

### 1. 创建环境隔离
- 进入仓库 `Settings -> Environments`。
- 点击 **New environment** 分别创建 `HK-Server` 和 `US-Server`。
- 将上述 7 个 Secrets 分别填入对应的 Environment 下（而不是 Repository secrets）。

### 2. 初始化新机
- GitHub Actions 运行 `🚀 Bootstrap` 时，在弹出的下拉菜单中选择对应的目标环境（如 `HK-Server`）。
- Actions 会自动从对应的“保险箱”取密钥进行部署。

### 3. 环境逻辑
- 你可以在 GitHub Actions 页面一眼看到每个环境目前的运行版本。
- 也可以设置“保护规则”，例如：推送到 `Production` 环境的代码必须经过你的手动点击批准。

---

# 🍼 零基础“保姆级”部署教程 (傻瓜版)

> **目标**：从零开始，在 GitHub Actions 上点一下，完成 VPS 全自动初始化。

### 第一步：生成“钥匙”对 (在你的本地电脑操作)

1.  在 Windows 或 Mac 的终端输入这一行并回车：
    ```powershell
    ssh-keygen -t ed25519 -f vps-ops-key -N ""
    ```
2.  你的当前目录下会生成两个文件：
    -   `vps-ops-key` (这是 **私钥**，对应钥匙)
    -   `vps-ops-key.pub` (这是 **公钥**，对应锁)
3.  用记事本打开它们，准备好内容。

---

### 第二步：获取 Cloudflare 的两个核心 Token

#### 1. Tunnel Token (`CF_TOKEN`)
-   登录 [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) 
-   点击左侧 `Networks` -> `Tunnels` -> `Create a tunnel`。
-   起个名（如 `vps-vm`），选择 `Docker`。
-   **看屏幕上的命令**，找到 `--token` 后面那一长串乱码（以 `eyJh...` 开头），复制它。
-   **格式示例**：`eyJhIjoi...` (一长串字母数字)

#### 2. DNS API Token (`CF_DNS_API_TOKEN`)
-   去 [API Tokens 页面](https://dash.cloudflare.com/profile/api-tokens)。
-   点击 `Create Token` -> 使用 `Edit zone DNS` 模板。
-   在 `Zone Resources` 选 `Specific zone` -> 选择你的域名。
-   点击 `Continue` -> `Create Token`。
-   **格式示例**：`abc123456789...` (通常 40 位左右)

---

### 第三步：获取坚果云备份密码 (可选)

-   登录坚果云 -> `账户信息` -> `安全选项` -> `第三方应用管理`。
-   点击 `添加应用` -> 输入 `vps-ops-backup`。
-   点击 `生成密码`。
-   **格式示例**：`abcd-efgh-ijkl-mnop` (带连字符的字母)

---

### 第四步：录入 GitHub Secrets (这是最重要的一步！)

1.  打开你的代码仓库页面 -> `Settings` -> `Secrets and variables` -> `Actions`。
2.  点击 `New repository secret`，一个个录入这 7 个密钥：

| 名称 | 如何获取 / 格式 |
|:---|:---|
| `VPS_HOST` | 你的 VPS 的 **公网 IP** (如 `123.45.67.89`) |
| `VPS_ROOT_PASS` | 供应商给你的 **root 账户原始密码** |
| `VPS_SSH_PRIVATE_KEY` | 拷贝第一步生成的 `vps-ops-key` 全文 (含 `-----BEGIN...`) |
| `VPS_SSH_PUBKEY` | 拷贝第一步生成的 `vps-ops-key.pub` 全文 (只有一行) |
| `VPS_ENV_CONTENT` | **全选复制** 仓库里的 `.env.example` 内容，把里面的 Token 换成你刚才撸到的。 |
| `VPS_SSH_PORT` | 直接填 `22222` (建议) |
| `VPS_USER` | 直接填 `sudor` (建议) |

---

### 第五步：起飞！🚀

1.  点击仓库顶部的 **Actions** 标签。
2.  点击左侧的 `🚀 Bootstrap: 初始化全新 VPS`。
3.  点击右侧的 `Run workflow` 按钮。
4.  如果是第一次，目标环境选 `Production` 即可，点击绿色按钮。
5.  **喝杯咖啡** 🫖。大约 5-10 分钟，当图标变绿，你的堡垒机就满血上线了！

---

## 🔒 手动安全加固（所有服务就绪后执行）

> **何时执行？** `bootstrap.yml` 跑完、容器正常、且**确认可以用 SSH 私钥从端口 22222 登录 `sudor` 账号**之后再执行。
>
> **为什么手动？** 锁端口/禁密码不可逆，操作前必须确认新的连接方式可用。

### 第一步：检查并确保 SSH 通道畅通

初始化完成后，系统默认进入**宽松登录模式**（双端口、双用户、双认证）。如果你想核实或手动设置，请确保配置如下：

```bash
sudo -i

cat > /etc/ssh/sshd_config.d/99-vps-ops.conf << 'EOF'
# 宽松模式认证：保持 22 和 22222 同时可用
Port 22
Port 22222
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
X11Forwarding no
EOF

# 重启 SSH 使得配置生效
systemctl restart ssh
```

### 第二步：防火墙确认

确保 UFW 放行了必要的端口：
```bash
ufw allow 22/tcp
ufw allow 22222/tcp
ufw --force enable
```

### 第二步：关闭云控制台端口 22

**阿里云控制台 → 安全组 → 入方向规则** → 将端口 22（SSH 系统规则，优先级 100）改为**拒绝**。

### 验证加固结果

```bash
# 本地执行: 新端口应可正常登录
ssh -i vps-ops-key -p 22222 sudor@<VPS_IP> echo "OK"

# 旧端口 22 应超时或被拒绝
ssh -o ConnectTimeout=5 -p 22 sudor@<VPS_IP>
# Connection refused 即为成功

# root 登录应被拒绝
ssh -i vps-ops-key -p 22222 root@<VPS_IP>
# Permission denied (publickey). 即为成功
```

---

## ☢️ 删机跑路与重建前：终极防爆验证清单

如果您打算验证这套极客架构的“毁机重建”全自动化容灾链（BDR），在您按下云服务商控制台里的“Delete”按钮前，请**务必**对照以下 5 条硬核防爆红线：

### 🚨 致命红线 (丢失=数据火葬场)
1. **`.env` 必须在本地有绝对安全的备份！**
   - **死穴**：里面包含的 `KOPIA_PASSWORD` 如果丢了，Cloudflare R2 里的快照全是对称加密的乱码，神仙也解不开！`R2_ACCESS_KEY_ID` 丢了连线都连不上。
   - **动作**：现在就 `cat .env` 把全文复制保存！
2. **检查未被 `git commit` 的本地手搓代码**
   - **死穴**：`init_host.sh` 或 GitOps 重建只会拉取 Github 最新的主分支。如果这期间您在 VPS 改了 `main.py` 却没 Push，重建时就会丢失逻辑！所有代码和配置**不由 Kopia 备份**！
   - **动作**：确认远程仓库代码是最新的。

### ⚠️ 高危绊脚石 (未处理=服务中断)
3. **Tailscale Auth Key 是否为“可复用”状态？**
   - **死穴**：Tailscale 默认生成的 Key 是**一次性**的！原机器用过就废了。重建时跑到 `tailscale up` 会报错，导致 Nginx-Relay 无法连到 NAS，DERP 无法鉴权！
   - **动作**：去控制台确保 Key 是 "Reusable" 并永不过期，或在 `.env` 里换新 Key。
4. **手动修改 `derp.660415.xyz` 的 DNS A 记录**
   - **死穴**：虽然依靠 Cloudflare Tunnel，网页服务能无视 IP 变动满血复活，但 **DERP 节点依赖纯真公网 IP 暴露**！
   - **动作**：VPS 重建后查到新 IP，必须立刻登录 CF Dashboard 修改 `derp.660415.xyz` 的 DNS 解析。
5. **Let's Encrypt 证书签发限流警告 (ACME)**
   - **死穴**：LE 官方对同一个域名每周只给 5 次正式证书签发。如果你一天内反复毁机重建超过 5 次，证书签发将被封禁一周！
   - **动作**：演练阶段请务必在 `.env` 设置 `ACME_STAGING=true`，等彻底定型了再签正式版！

---

## 📝 进阶教程：如何重签 ACME 正式证书？

**Q: 拿测试证书调试好了，想换成正式证书，需要把服务器完全格式化或者重新跑 `init_host.sh` 吗？**
**A: 完全不需要！VPS 核心业务全是由 Docker 隔离管控的，只需原地强制重启签发相关的容器即可。**

**无痛无感重签 3 步曲：**

```bash
# 进入部署目录
cd /opt/vps-dmz/

# 1. 更改环境变量为生产模式 (ACME_STAGING=false)
sed -i 's/ACME_STAGING=true/ACME_STAGING=false/' .env

# 2. 清除残留的自签名/测试证书文件 (如果不删，acme-init 会判定证书存在直接跳过)
rm -rf data/acme/*

# 3. 仅对证书签发与使用相关的 3 个容器进行“脱壳重铸”！
# --force-recreate 会让配置瞬间生效，其他十几个业务容器 (音乐、面板等) 毫发无损，无需停机。
docker compose up -d --force-recreate acme acme-init derper
```

> **注意**：执行这行代码后，你可以通过 `docker logs -f acme-init` 看到签发过程，当显示签发成功后，`derper` 会立刻读取到被覆写的正规证书。此生一劳永逸（后续 `acme` 守护进程会自动续期）。

---

## 🧹 进阶教程：卸载阿里云官方监控与云安全中心 (可选)

如果你使用的是 **阿里云 VPS**，默认系统后台会常驻运行 `AliYunDun`（云安全中心/安骑士）和 `AliYunDunMonitor`（云监控）守护进程。

对于本项目的 2C2G 平民架构来说，**强烈建议卸载**：
1. **浪费宝贵内存**：常驻占用约 30MB 内存及间歇性 CPU 波动，全都是用来跑 Docker 业务的，给它们纯属浪费。
2. **功能严重重叠**：VPS-OPS 已经全面锁死了 SSH 端口、启用了 Fail2Ban 与 UFW，防御已然成型，不再需要扫盘。并且我们有 UptimeKuma 等监控。
3. **强侵入性**：作为 Root 级组件，它容易对我们在内网穿透（如 nginx-relay）过程中的一些合法代理流量产生误报乃至阻断。

**卸载对系统无负面影响（仅在阿里云网页端看不到监控图），只需以 root 身份执行以下命令进行“一键净化”：**

```bash
# 1. 卸载阿里云盾 (云安全中心/安骑士)
wget -qO- http://update.aegis.aliyun.com/download/uninstall.sh | bash
wget -qO- http://update.aegis.aliyun.com/download/quartz_uninstall.sh | bash

# 2. 卸载阿里云监控插件
/usr/local/cloudmonitor/wrapper/bin/cloudmonitor.sh stop
/usr/local/cloudmonitor/wrapper/bin/cloudmonitor.sh remove
rm -rf /usr/local/cloudmonitor

# 3. 彻底清理系统服务残留
systemctl stop aliyun.service
systemctl disable aliyun.service
rm -f /etc/systemd/system/aliyun.service
rm -rf /usr/local/aegis
rm -rf /usr/local/share/assist-daemon
systemctl daemon-reload
```
执行完毕后，可通过 `top` 或 `htop` 查看，烦人的 `AliYunDun` 进程将彻底从你的系统中消失，又省下了一大块干净的运行资源！

---

<div align="center">

**Enjoy your new server! 🥂**

Made with ❤️ by FenLynn

</div>

