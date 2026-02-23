"""
VPS-OPS — /ops/* 路由鉴权模块
=============================================
通过 FastAPI Depends 机制注入，仅保护 /ops/ 前缀路由。
客户端需在 Header 中携带：X-VPS-Token: <VPS_TOKEN>
Token 从环境变量 VPS_TOKEN 读取，不硬编码。
"""

import os
from fastapi import Header, HTTPException

# 从环境变量读取，启动时确定
_VPS_TOKEN = os.getenv("VPS_TOKEN", "")


async def verify_token(x_vps_token: str = Header(..., alias="x-vps-token")):
    """FastAPI Depends 鉴权依赖 — 用于 /ops/* 路由"""
    if not _VPS_TOKEN:
        raise HTTPException(
            status_code=500,
            detail="服务器配置错误：VPS_TOKEN 环境变量未设置",
        )
    if x_vps_token != _VPS_TOKEN:
        raise HTTPException(
            status_code=403,
            detail="Forbidden: 无效的访问令牌",
        )
