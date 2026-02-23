"""
VPS-OPS v2.1 — FastAPI 统一 API 网关
=============================================================================
路由规划:
  /v1/{path}     → new-api:3000       (AI 接口，流式 SSE 透传，300s 超时)
  /music/{path}  → music-api:3000     (音乐 API，流式大文件透传，60s 超时)
  /webhook/{path}→ nginx-relay:80     (NAS Webhook 转发，30s 超时)
  /ops/quant/signal   → 本地业务逻辑  (A股量化信号接收，Token 鉴权)
  /ops/research/paper → 本地业务逻辑  (科研文献归档，Token 鉴权)
  /ops/health    → 本地           (受保护健康检查)
  /health        → 本地           (公开健康检查，供 CF 探针)
  /              → API 状态页
=============================================================================
v2.1 修复:
  - proxy_request 全量加载 → stream_proxy 流式透传（修复 SSE 打字机效果 & 大文件内存溢出）
  - 各路由独立超时（AI:300s / Music:60s / Webhook:30s）
  - 废弃无效的 FASTAPI_SECRET_KEY，改用 VPS_TOKEN Depends 保护 /ops/*
  - Dockerfile COPY . . 确保新模块打包进镜像
"""

import os
import httpx
from fastapi import FastAPI, Request, Depends, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse, Response

from auth import verify_token
from schemas import QuantSignal, ResearchPaper

# ─── 配置 ─────────────────────────────────────────────────────────────────────
NEW_API_URL = os.getenv("NEW_API_URL", "http://new-api:3000")
MUSIC_API_URL = os.getenv("MUSIC_API_URL", "http://music-api:3000")
NGINX_RELAY_URL = os.getenv("NGINX_RELAY_URL", "http://nginx-relay:80")

app = FastAPI(
    title="VPS-OPS API Gateway",
    description="统一 API 网关 v2.1 — 流式透传 + /ops/ 数据中台",
    version="2.1.0",
)


# ─── 流式代理核心函数 ─────────────────────────────────────────────────────────
async def stream_proxy(
    request: Request,
    target_url: str,
    strip_prefix: str = "",
    timeout: float = 60.0,
) -> StreamingResponse:
    """
    将请求流式代理到目标后端，不在内存中缓存响应体。
    适用于：SSE 打字机输出 / 音频大文件 / 任何流式场景。
    """
    # 构建目标 URL
    path = request.url.path
    if strip_prefix and path.startswith(strip_prefix):
        path = path[len(strip_prefix) :]
    if not path.startswith("/"):
        path = "/" + path
    url = f"{target_url}{path}"
    if request.url.query:
        url = f"{url}?{request.url.query}"

    # 过滤请求头（移除 host，避免后端路由混乱）
    headers = {k: v for k, v in request.headers.items() if k.lower() != "host"}

    # 读取请求体（API 请求 body 通常很小）
    body = await request.body()

    # 建立流式 HTTP 连接
    client = httpx.AsyncClient(timeout=httpx.Timeout(timeout))
    req = client.build_request(request.method, url, headers=headers, content=body)

    try:
        resp = await client.send(req, stream=True)
    except httpx.RequestError as e:
        await client.aclose()
        return JSONResponse(
            status_code=502,
            content={"error": "Bad Gateway", "detail": str(e), "target": url},
        )

    # 过滤响应头（移除可能导致客户端解码失败的传输编码头）
    skip_headers = {"content-encoding", "transfer-encoding", "content-length"}
    response_headers = {
        k: v for k, v in resp.headers.items() if k.lower() not in skip_headers
    }

    async def generate():
        """逐块 yield，真正的流式输出"""
        try:
            async for chunk in resp.aiter_bytes(chunk_size=8192):
                yield chunk
        finally:
            await resp.aclose()
            await client.aclose()

    return StreamingResponse(
        generate(),
        status_code=resp.status_code,
        headers=response_headers,
        media_type=resp.headers.get("content-type"),
    )


# ─── 公开路由 ─────────────────────────────────────────────────────────────────


@app.get("/")
async def root():
    """API 网关状态页"""
    return {
        "service": "VPS-OPS API Gateway",
        "version": "2.1.0",
        "routes": {
            "/v1/*": "New API (AI 接口，SSE 流式)",
            "/music/*": "Music API (音乐接口，流式大文件)",
            "/webhook/*": "Webhook Relay (NAS 转发)",
            "/ops/*": "数据中台 (需 X-VPS-Token 鉴权)",
            "/health": "健康检查",
        },
    }


@app.get("/health", tags=["系统监控"])
async def health():
    """公开健康检查 — 供 Cloudflare / Uptime Kuma 探针使用"""
    return {"status": "ok"}


@app.api_route(
    "/v1/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    tags=["AI 接口"],
)
async def proxy_ai(request: Request):
    """代理到 New API — 支持 SSE 流式打字机输出，超时 300s"""
    return await stream_proxy(request, NEW_API_URL, timeout=300.0)


@app.api_route(
    "/music/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    tags=["音乐接口"],
)
async def proxy_music(request: Request):
    """代理到 Music API — 流式大文件透传，超时 60s"""
    return await stream_proxy(
        request, MUSIC_API_URL, strip_prefix="/music", timeout=60.0
    )


@app.api_route(
    "/webhook/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    tags=["Webhook"],
)
async def proxy_webhook(request: Request):
    """代理到 Nginx Relay → NAS，超时 30s"""
    return await stream_proxy(
        request, NGINX_RELAY_URL, strip_prefix="/webhook", timeout=30.0
    )


# ─── /ops/ 数据中台路由（均需 X-VPS-Token 鉴权）────────────────────────────


@app.post("/ops/quant/signal", tags=["A股量化"])
async def receive_quant_signal(
    signal: QuantSignal,
    _: None = Depends(verify_token),
):
    """
    接收 A股量化交易信号。
    外部调用：POST https://api.660415.xyz/ops/quant/signal
    Header:   X-VPS-Token: <VPS_TOKEN>
    """
    # TODO: 对接 SQLite / Cloudflare D1 持久化
    # TODO: 对接 Gotify / Server酱 推送买卖点通知
    print(
        f"[量化引擎] {signal.symbol} → {signal.signal_type}"
        f"  策略: {signal.strategy_name}  价格: {signal.price}"
    )
    return {
        "status": "success",
        "message": "量化信号已接收",
        "data": signal.model_dump(),
    }


@app.post("/ops/research/paper", tags=["学术科研"])
async def receive_research_paper(
    paper: ResearchPaper,
    _: None = Depends(verify_token),
):
    """
    接收高功率光纤激光器科研文献元数据。
    外部调用：POST https://api.660415.xyz/ops/research/paper
    Header:   X-VPS-Token: <VPS_TOKEN>
    """
    # TODO: 触发 Cloudflare Pages MkDocs 重新构建
    print(f"[学术引擎] 归档: {paper.title[:40]}  标签: {paper.tags}")
    return {
        "status": "success",
        "message": "文献元数据已归档",
        "tags_indexed": paper.tags,
    }


@app.get("/ops/health", tags=["A股量化", "学术科研"])
async def ops_health(_: None = Depends(verify_token)):
    """受保护健康检查 — 验证 Token 是否配置正确"""
    return {"status": "ok", "role": "Data_Hub_Backend"}
