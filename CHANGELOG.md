# Changelog

## [v2.0.0] - 2026-02-21 (DMZ 无状态堡垒机升级)

### 🏗️ 架构重构
- **统一编排**: 将三层 Compose 文件 (`00-infra/`, `01-stable/`, `02-management/`) 合并为 `compose/docker-compose.yml`
- **四维隔离**: 部署目录 `/opt/vps-dmz/` 实现代码/配置/数据/日志完全隔离
- **零端口暴露**: 除 DERP 外所有服务通过 Cloudflare Tunnel 访问
- **域名体系**: 统一 `660415.xyz` 二级域名规范

### ✨ 新增功能
- **FastAPI 统一网关** (`api.660415.xyz`): 路由分发到 new-api、music-api、nginx-relay
- **Music API** + **网易云解灰**: YesPlayMusic 后端 + unblock-netease 代理级联
- **Nginx Relay**: 公私网桥接，通过 Tailscale 转发 Webhook 到家庭 NAS
- **原子性备份** (`backup_kopia.sh`): SQLite pause → snapshot → unpause 铁律
- **证书续期回调** (`cert_renew.sh`): 自动重启 DERP 加载新证书
- **CI/CD 自动部署** (`deploy.yml`): SSH 推送部署到 VPS

### 🔧 改进
- `init_host.sh` 移至 `scripts/` 并全面重写
- `.env.example` 新增 BASE_DIR、MAIN_DOMAIN 等变量
- Docker 网络从 `vps-net` 更名为 `vps_tunnel_net`
- Kopia 改为外部触发模式 (宿主机 crontab + docker exec)

---

## [v1.0.0] - 2026-02-17 (One-Key Release)

### ✨ Major Features
- **One-Key Deployment**: Fully automated `init_host.sh` for zero-config setup.
- **China Network Optimization**: Integrated `hub.rat.dev` mirror and optimized DNS.
- **Security Hardening**: Custom SSH port (22222), Fail2Ban integration, and strict firewall rules.
- **Service Orchestration**: Dual-layer architecture (Infrastructure + Business) with health checks.
- **Automated SSL**: `acme-init` with auto-renewal and multi-domain support.

### 🐛 Bug Fixes & Improvements
- Fixed ECC certificate path detection in `acme-init` (force copy logic).
- Fixed shell syntax errors in initialization scripts.
- Added strict validation for `.env` and certificate integrity.
- Handled LetsEncrypt rate limiting with clear error messages.
- Comprehensive documentation update (Chinese README.md).

## [Unreleased]
All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-02-15
### Added
- Initial release of `vps-ops`.
- Host initialization script `init_host.sh` with Aliyun optimization.
- Layer 0 (Infra): `acme.sh`, `cloudflared`, `watchtower`.
- Layer 1 (Stable): `derper`, `new-api`, `uptime-kuma`, `backup`.
- Automated Git hooks and `.editorconfig`.
- Security policy and Token Guide.
