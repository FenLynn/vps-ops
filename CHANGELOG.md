# Changelog

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
