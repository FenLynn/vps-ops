"""
VPS-OPS v2.0 — FastAPI 统一 API 网关
=============================================================================
路由规划:
  api.660415.xyz/v1/chat/*   → 代理到 new-api:3000
  api.660415.xyz/music/*     → 代理到 music-api:3000
  api.660415.xyz/webhook/*   → 代理到 nginx-relay:80
  api.660415.xyz/health      → 本地健康检查
  api.660415.xyz/             → API 文档/状态页
=============================================================================
"""

import os
import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse

# ─── 配置 ─────────────────────────────────────────────────────────────────────
NEW_API_URL = os.getenv("NEW_API_URL", "http://new-api:3000")
MUSIC_API_URL = os.getenv("MUSIC_API_URL", "http://music-api:3000")
NGINX_RELAY_URL = os.getenv("NGINX_RELAY_URL", "http://nginx-relay:80")

app = FastAPI(
    title="VPS-OPS API Gateway",
    description="统一 API 网关 — 路由分发到后端服务",
    version="2.0.0",
)

# 异步 HTTP 客户端 (连接池复用)
http_client = httpx.AsyncClient(timeout=30.0, follow_redirects=True)


# ─── 通用代理函数 ─────────────────────────────────────────────────────────────
async def proxy_request(
    request: Request, target_url: str, strip_prefix: str = ""
) -> Response:
    """将请求代理到目标后端服务"""
    # 构建目标 URL
    path = request.url.path
    if strip_prefix and path.startswith(strip_prefix):
        path = path[len(strip_prefix) :]
    if not path.startswith("/"):
        path = "/" + path

    url = f"{target_url}{path}"
    if request.url.query:
        url = f"{url}?{request.url.query}"

    # 转发请求头
    headers = dict(request.headers)
    headers.pop("host", None)

    # 读取请求体
    body = await request.body()

    try:
        resp = await http_client.request(
            method=request.method,
            url=url,
            headers=headers,
            content=body,
        )
        return Response(
            content=resp.content,
            status_code=resp.status_code,
            headers=dict(resp.headers),
        )
    except httpx.RequestError as e:
        return JSONResponse(
            status_code=502,
            content={"error": "Bad Gateway", "detail": str(e), "target": url},
        )


# ─── 路由 ─────────────────────────────────────────────────────────────────────


@app.get("/")
async def root():
    """API 网关状态页"""
    return {
        "service": "VPS-OPS API Gateway",
        "version": "2.0.0",
        "routes": {
            "/v1/chat/*": "New API (AI 接口)",
            "/music/*": "Music API (音乐接口)",
            "/webhook/*": "Webhook Relay (NAS 转发)",
            "/health": "健康检查",
        },
    }


@app.get("/health")
async def health():
    """健康检查端点"""
    return {"status": "ok"}


@app.api_route(
    "/v1/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
)
async def proxy_new_api(request: Request):
    """代理到 New API (AI 接口网关)"""
    return await proxy_request(request, NEW_API_URL, strip_prefix="")


@app.api_route(
    "/music/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
)
async def proxy_music_api(request: Request):
    """代理到 Music API (音乐接口)"""
    return await proxy_request(request, MUSIC_API_URL, strip_prefix="/music")


@app.api_route(
    "/webhook/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
)
async def proxy_webhook(request: Request):
    """代理到 Nginx Relay (NAS 转发)"""
    return await proxy_request(request, NGINX_RELAY_URL, strip_prefix="/webhook")


# ─── 生命周期事件 ─────────────────────────────────────────────────────────────
@app.on_event("shutdown")
async def shutdown():
    await http_client.aclose()
