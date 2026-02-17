# 🚀 VPS-Ops: 生产级服务器全自动部署方案

<div align="center">

**零基础 · 全自动 · 甚至不需要公网 IP**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-compose-blue)](https://docs.docker.com/compose/)
[![Cloudflare](https://img.shields.io/badge/cloudflare-zero--trust-orange)](https://www.cloudflare.com/)

</div>

---

## 📖 这是一个什么项目？

您是否经历过：
*   买了一台新 VPS，要花半天时间安装 Docker、配置防火墙、申请 SSL 证书？
*   想在服务器上跑个 AI（OneAPI）或者仪表盘（Homarr），却被 Nginx 反向代理搞得头大？
*   服务器裸奔在公网，每天被扫描几十万次，提心吊胆？
*   想备份数据，却只能手动打包下载，重装系统后恢复极其痛苦？

**VPS-Ops 就是为了解决这些问题而生的。**

它是一个 **"基础设施即代码 (IaC)"** 的自动化脚本。您只需要填好几个密码，运行一条命令，它就会像变魔术一样，自动把一台还有余温的新 VPS，变成一个**安全、现代、功能强大**的私人数据中心。

---

## �️ 它是如何工作的？（原理篇）

为了保证稳定和易维护，我们将系统分成了三层（这也是您会在文件夹里看到的结构）：

```mermaid
graph TD
    User((用户)) --> CF[Cloudflare 全球边缘节点]
    CF --> Tunnel[🔒 安全隧道 (无需公网IP)]
    
    subgraph VPS [您的服务器]
        Tunnel --> Traefik[网关/TLS 终结]
        
        subgraph Layer0 [Layer 0: 基础设施]
            ACME[acme.sh 证书自动续期]
            Watchtower[自动更新]
        end
        
        subgraph Layer1 [Layer 1: 核心业务]
            NewAPI[AI 接口网关]
            Uptime[监控面板]
            Derp[Tailscale 中继]
        end
        
        subgraph Layer2 [Layer 2: 管理面板]
            Dockge[容器管理]
            Homarr[聚合导航页]
        end
        
        subgraph Backup [�️ 灾备系统]
            Kopia[Kopia 增量备份] --> WebDAV[☁️ 云端网盘]
        end
    end
```

1.  **Layer 0 (地基)**：负责脏活累活。自动申请 HTTPS 证书、建立 Cloudflare 隧道（让外网能安全访问内网）、自动更新软件。
2.  **Layer 1 (核心)**：最重要的业务。比如 AI 接口(OneAPI)、监控(Uptime Kuma)。它们最先启动，最后关闭。
3.  **Layer 2 (管理)**：可视化的面板。让您通过漂亮的网页管理服务器，而不是对着黑框框敲命令。

---

## �️ 准备工作

在开始之前，您需要准备以下 4 样东西（就像炒菜前要备料）：

1.  **一台 VPS**：
    *   推荐配置：2核 2G 内存以上（虽然 1核1G 也能跑，但有点勉强）。
    *   系统：推荐 **Debian 11/12** 或 Ubuntu 20.04/22.04（CentOS 也可以，但稍微麻烦点）。
2.  **一个域名**：
    *   必须托管在 **Cloudflare**（因为我们需要它的 API 来自动申请证书）。
3.  **Cloudflare 账号**：
    *   用于创建 **Tunnel**（隧道）。这是本项目的核心，它能让您的服务在不开放 80/443 端口的情况下被外网访问，极其安全。
4.  **WebDAV 网盘**（可选，但强烈推荐）：
    *   推荐 **TeraCloud** (免费 10GB) 或坚果云。用于存放每日自动备份的数据。

---

## ⚡️ 极速安装指南

### 第一步：获取代码
登录您的 VPS（推荐使用 SSH 工具），输入：

```bash
# 1. 安装 git (如果已安装可跳过)
apt update && apt install -y git  # Debian/Ubuntu
# yum install -y git              # CentOS

# 2. 下载本项目
git clone https://github.com/FenLynn/vps-ops.git
cd vps-ops
```

### 第二步：配置“秘密文件” (.env)
这是最关键的一步。我们需要告诉脚本您的密码和 Token。

```bash
# 复制模板文件
cp .env.example .env

# 编辑它 (小白推荐使用 nano，或者在本地改好传上去)
nano .env
```

**您只需重点关注这几项（填错会导致服务无法启动）：**

| 变量名 | 必填 | 作用 | 获取方式 |
| :--- | :--- | :--- | :--- |
| `CF_TOKEN` | ✅ | Cloudflare 隧道的身份证 | [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) -> Networks -> Tunnels -> Create |
| `CF_DNS_API_TOKEN` | ✅ | 申请 SSL 证书的权限 | [Cloudflare API](https://dash.cloudflare.com/profile/api-tokens) -> Create -> Edit zone DNS |
| `KOPIA_PASSWORD` | ✅ | 数据备份的加密密码 | **自己设定**（一定要复杂！丢了数据找不回！） |
| `WEBDAV_URL` | ✅ | 备份传到哪里去 | 您的网盘 WebDAV 地址 |
| `NEW_API_ADMIN_PASSWORD` | ✅ | AI 面板的管理员密码 | **自己设定** |

*(详细的 Token 获取图文教程，请看本文末尾的附录)*

### 第三步：一键发射 🚀
确认 `.env` 没问题后，深吸一口气，执行：

```bash
sudo bash init_host.sh
```

**接下来会发生什么？**
1.  **系统初始化**：脚本会优化内核参数，安装 Docker，创建一个叫 `sudor` 的安全用户。
2.  **网络优化**：自动配置国内镜像源，再也不用担心拉取镜像卡在 0% 了。
3.  **启动服务**：依次启动 Layer 0, 1, 2 的所有服务。
4.  **自动恢复**：如果是新机器且配置了备份，它甚至会自动从网盘把以前的数据拉回来！

喝杯咖啡，等待出现 **"✅ All systems functional!"** 字样。

---

## 🖥️ 如何访问我的服务？

安装完成后，您可能会问：“IP:端口 怎么访问不了？”
**是的，为了安全，我们默认关闭了所有端口（只留了 SSH）！**

请去 Cloudflare Zero Trust 后台，配置 **Public Hostnames**：

| 服务名称 | 建议子域名 | 容器内部地址 (Service) |
| :--- | :--- | :--- |
| **New API (AI)** | `api.yourdomain.com` | `http://new-api:3000` |
| **Uptime Kuma** | `status.yourdomain.com` | `http://uptime-kuma:3001` |
| **Dockge (管理)** | `dockge.yourdomain.com` | `http://dockge:5001` |
| **Homarr (导航)** | `home.yourdomain.com` | `http://homarr:7575` |

**💡 安全小贴士**：对于 `dockge` 和 `homarr` 这种管理后台，强烈建议在 Cloudflare 是开启 **Access**（身份验证），这样别人访问时需要输入邮箱验证码，安全性 MAX！

---

## 🛡️ 关于数据备份 (小白必读)

我们采用的是 **企业级** 的 Kopia 备份方案。

*   **它存哪了？** 您配置的 WebDAV 网盘。
*   **存了什么？** 您的所有配置、数据库、证书。不包含代码（代码在 git 里）。
*   **安全吗？** 极其安全。数据在离服务器前就被加密了，网盘管理员也看不了。
*   **怎么恢复？**
    *   **自动**：新机器填好 `.env` 运行脚本，自动恢复。
    *   **手动**：
        ```bash
        # 想回滚到昨天的状态？
        docker exec -it kopia kopia snapshot restore latest /source
        ```

---

## ❓ 常见问题 (Q&A)

**Q: 脚本运行到一半断开了怎么办？**
A: 没事，直接重新运行 `sudo bash init_host.sh`。脚本是“幂等”的，意思是运行 1 次和运行 100 次效果一样，不会破坏现有数据。

**Q: 证书申请失败了？**
A: 检查 `CF_DNS_API_TOKEN` 是否有多余空格？Cloudflare 偶尔会抽风，可以查看日志：`docker logs acme-init`。

**Q: 我想修改端口？**
A: 编辑 `config.ini` 文件，然后重新运行脚本即可。

---

<div align="center">

**Enjoy your new server! 🥂**

如果有问题，欢迎提交 Issue。

</div>
