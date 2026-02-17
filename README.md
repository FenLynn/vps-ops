# VPS-Ops 自动化部署方案

<div align="center">

**一键部署生产级 VPS 基础设施 | 国内网络优化 | 零配置自动化**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-compose-blue)](https://docs.docker.com/compose/)
[![Cloudflare](https://img.shields.io/badge/cloudflare-zero--trust-orange)](https://www.cloudflare.com/)

</div>

---

## 📖 目录

- [项目简介](#-项目简介)
- [核心特性](#-核心特性)
- [快速开始](#-快速开始)
- [Token 获取指南](#-token-获取指南)
- [服务架构](#-服务架构)
- [配置说明](#-配置说明)
- [常见问题](#-常见问题)
- [更新日志](#-更新日志)

---

## 🎯 项目简介

`vps-ops` 是一套针对国内网络环境深度优化的 VPS 自动化部署方案，通过 **一条命令** 完成从系统初始化到服务上线的全流程。

### 适用场景
- ✅ 新购 VPS 快速上线
- ✅ 系统重装后快速恢复
- ✅ 多台服务器批量部署
- ✅ 个人/小团队基础设施搭建

---

## ✨ 核心特性

### 🚀 一键自动化
```bash
sudo bash init_host.sh
```
自动完成：系统优化、Docker 安装、证书申请、服务启动

### 🇨🇳 国内网络优化
- **Docker 镜像加速**：使用 `hub.rat.dev` 国内镜像源
- **Git 代理支持**：可选配置 GitHub 加速
- **DNS 优化**：自动配置最优 DNS 服务器

### 🔒 安全加固
- **SSH 端口修改**：默认 22222，避免扫描攻击
- **Fail2Ban 防护**：自动封禁暴力破解 IP
- **防火墙配置**：仅开放必要端口

### 📦 服务编排
- **双层架构**：基础设施层 + 业务层分离
- **自动更新**：Watchtower 每日凌晨 4 点自动更新镜像
- **健康检查**：所有服务内置健康检测

---

## 🚀 快速开始

### 前置要求
- **操作系统**：CentOS 7+、Ubuntu 20.04+、Debian 10+
- **权限**：root 或 sudo 权限
- **网络**：能访问 GitHub 和 Docker Hub（或使用镜像源）

### 部署步骤

#### 1. 安装 Git
```bash
# CentOS/AlmaLinux
yum install -y git

# Ubuntu/Debian
apt update && apt install -y git
```

#### 2. 克隆仓库
```bash
git clone https://github.com/FenLynn/vps-ops.git
cd vps-ops
```

#### 3. 配置环境变量
```bash
cp .env.example .env
vi .env
```

**必填项**：
```ini
# Cloudflare Tunnel Token（用于内网穿透）
CF_TOKEN=eyJhIjoi...

# Cloudflare DNS API Token（用于自动申请 SSL 证书）
CF_DNS_API_TOKEN=your_cloudflare_dns_token

# Derper 域名（必须是您在 Cloudflare 托管的域名）
DERP_DOMAIN=derp.yourdomain.com
```

**可选项**：
```ini
# PushPlus Token（微信通知）
PUSHPLUS_TOKEN=your_pushplus_token

# GitHub Token（用于拉取私有镜像，可选）
GH_TOKEN=ghp_...
```

#### 4. 一键部署
```bash
sudo bash init_host.sh
```

#### 5. 验证部署
```bash
docker ps
```

所有容器应显示 `Up` 或 `Up (healthy)` 状态。

---

## 🔑 Token 获取指南

### 1. CF_TOKEN（Cloudflare Tunnel）
用于将内网服务安全暴露到公网，无需开放端口。

**获取步骤**：
1. 访问 [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. 导航到 **Networks > Tunnels**
3. 点击 **Create a tunnel**
4. 命名为 `vps-ops`（或任意名称）并保存
5. 在"Install connector"步骤中，复制 Docker 命令中的 **token** 部分
   ```bash
   # 示例命令
   docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJh...
   # 👆 只需要复制 eyJh... 这部分
   ```

### 2. CF_DNS_API_TOKEN（DNS API）
用于通过 DNS 验证自动申请和续期 SSL 证书。

**获取步骤**：
1. 访问 [Cloudflare Profile > API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. 点击 **Create Token**
3. 选择 **Edit zone DNS** 模板
4. 在"Zone Resources"下，选择 **Include > Specific zone > yourdomain.com**
5. 点击 **Continue to summary**，确认权限后点击 **Create Token**
6. **立即复制 Token**（只显示一次）

### 3. PUSHPLUS_TOKEN（可选 - 微信通知）
用于接收系统更新、备份完成等通知。

**获取步骤**：
1. 访问 [PushPlus](http://www.pushplus.plus/)
2. 使用微信扫码登录
3. 在首页/控制台复制您的 **Token**

### 4. TAILSCALE_AUTH_KEY（可选 - 应急访问）
当 SSH 无法连接时，通过 Tailscale 提供备用访问通道。

**获取步骤**：
1. 访问 [Tailscale Admin Console > Settings > Keys](https://login.tailscale.com/admin/settings/keys)
2. 点击 **Generate auth key**
3. （可选）勾选 **Reusable**（如果经常重装系统）
4. 添加标签如 `tag:server`（推荐）
5. 点击 **Generate** 并复制密钥（以 `tskey-` 开头）

---

## 🏗️ 服务架构

### Layer 0: 基础设施层 (`00-infra`)
| 服务 | 用途 | 端口 |
|------|------|------|
| **acme.sh** | SSL 证书自动续期 | - |
| **cloudflared** | Cloudflare Tunnel 内网穿透 | - |
| **watchtower** | Docker 镜像自动更新 | - |
| **acme-init** | 首次证书申请（一次性任务） | - |

### Layer 1: 业务层 (`01-stable`)
| 服务 | 用途 | 端口 | 访问方式 |
|------|------|------|----------|
| **derper** | Tailscale DERP 中继服务器 | 33445/TCP, 3478/UDP | 公网直连 |
| **new-api** | AI API 网关 | 3000 | Cloudflare Tunnel |
| **uptime-kuma** | 服务监控面板 | 3001 | Cloudflare Tunnel |
| **backup** | 自动备份服务 | - | 每日凌晨 3 点执行 |

---

### Layer 2: 管理层 (`02-management`)
| 服务 | 用途 | 端口 | 访问方式 |
|------|------|------|----------|
| **Dockge** | 容器/Stack 管理 | - | Cloudflare Tunnel |
| **Homarr** | 聚合仪表盘 | - | Cloudflare Tunnel |

---

## ⚙️ 配置说明

### 全局配置 (`config.ini`)
```ini
# Docker 数据根目录
DOCKER_ROOT=/nfs/docker

# SSH 端口（默认 22222，避免扫描）
SSH_PORT=22222

# Derper 端口
DERP_PORT=33445
DERP_STUN_PORT=3478

# 管理员用户名
ADMIN_USER=sudor

# Docker 网络名称
DOCKER_NET=vps-net
```

### 访问管理服务 (Dockge & Homarr)
由于采用了零端口暴露的安全策略，您无法通过 IP:端口 访问。必须配置 Cloudflare Tunnel：

1. **Dockge 配置**:
   - Public Hostname: `dockge.yourdomain.com`
   - Service: `http://dockge:5001`
   - **强烈建议**: 在 Cloudflare Zero Trust 中开启 Access (邮箱验证)

2. **Homarr 配置**:
   - Public Hostname: `home.yourdomain.com`
   - Service: `http://homarr:7575`

---

## ❓ 常见问题

### Q1: 部署失败，提示 "certificate not found"
**原因**：LetsEncrypt 速率限制（每个域名每周最多 5 张证书）  
**解决**：
- 等待 7 天后重试
- 或使用不同的子域名（如 `derp2.yourdomain.com`）

### Q2: Derper 一直重启
**排查步骤**：
```bash
# 1. 查看 Derper 日志
docker logs derper --tail 50

# 2. 查看证书生成日志
docker logs acme-init

# 3. 检查证书文件
ls -la /nfs/docker/global/certs/derp.yourdomain.com/
```

**常见原因**：
- 证书文件为空（限流导致）
- 域名未正确配置 DNS
- `.env` 中 `DERP_DOMAIN` 填写错误

### Q3: 如何访问内网服务（new-api、uptime-kuma）？
通过 Cloudflare Tunnel 配置公共主机名：
1. 访问 [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. 导航到 **Networks > Tunnels > vps-ops**
3. 点击 **Public Hostname**
4. 添加规则：
   - **Subdomain**: `api`
   - **Domain**: `yourdomain.com`
   - **Service**: `http://new-api:3000`

### Q4: 如何更新服务？
**自动更新**（推荐）：
Watchtower 每日凌晨 4 点自动检查并更新所有镜像。

**手动更新**：
```bash
cd /root/vps-ops
git pull origin main
cd 00-infra && docker compose pull && docker compose up -d
cd ../01-stable && docker compose pull && docker compose up -d
```

### Q5: 如何备份数据？
**自动备份**：
- 时间：每日凌晨 3 点
- 位置：`/nfs/docker/backups/`
- 保留：最近 7 天

**手动备份**：
```bash
docker exec backup backup
```

---

## 📝 更新日志

详见 [CHANGELOG.md](CHANGELOG.md)

---

## 🔒 安全策略

详见 [SECURITY.md](SECURITY.md)

---

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

## 🙏 致谢

- [acme.sh](https://github.com/acmesh-official/acme.sh) - 自动化 SSL 证书管理
- [Cloudflare](https://www.cloudflare.com/) - Zero Trust 网络
- [Tailscale](https://tailscale.com/) - 安全的点对点网络
- [Watchtower](https://containrrr.dev/watchtower/) - 自动化容器更新

---

<div align="center">

**如有问题，欢迎提交 [Issue](https://github.com/FenLynn/vps-ops/issues)**

Made with ❤️ by FenLynn

</div>
