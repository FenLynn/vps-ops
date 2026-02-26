"""
VPS-OPS v2.2 — FastAPI 统一 API 网关
=============================================================================
路由规划 (精简版，已移除旧式代理占位符):
  /webhook/{path} → nginx-relay:80     (NAS Webhook 透传，30s 超时)
  /ops/quant/signal   → 本地业务逻辑  (A股量化信号接收，Token 鉴权 + PushPlus 推送)
  /ops/research/paper → 本地业务逻辑  (科研文献归档，Token 鉴权 + PushPlus 推送)
  /ops/health    → 本地           (受保护健康检查)
  /health        → 本地           (公开健康检查，供 CF 探针)
  /              → API 状态页

已清理/移除:
  /v1/*  — New-API (new-api 服务已从 compose 移除，存根删除)
  /music/* — Music API (YesPlayMusic 已全栈回归 VPS 同网，网关不再需要转发)

v2.2 改动:
  - 移除 /v1/ New-API 存根和 /music/ 代理路由
  - 新增 send_pushplus 异步工具：/ops/ 路由收到请求后实时推送微信通知
  - ResearchPaper 补充 published_date 可选字段
  - 清理冗余的 import json 和 Response 导入
"""

import os
import httpx
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, Depends
from fastapi.responses import StreamingResponse, JSONResponse

from auth import verify_token
from schemas import QuantSignal, ResearchPaper

# ─── 配置 ─────────────────────────────────────────────────────────────────────
NGINX_RELAY_URL = os.getenv("NGINX_RELAY_URL", "http://nginx-relay:80")
PUSHPLUS_TOKEN = os.getenv("PUSHPLUS_TOKEN", "")


# ─── PushPlus 微信推送工具函数 ──────────────────────────────────────────────────
async def send_pushplus(title: str, content: str) -> None:
    """异步微信推送，Token 为空时静默跳过，推送失败不影响主业务。"""
    if not PUSHPLUS_TOKEN:
        return
    try:
        assert _http_client is not None
        await _http_client.post(
            "http://www.pushplus.plus/send",
            json={
                "token": PUSHPLUS_TOKEN,
                "title": title,
                "content": content,
                "template": "markdown",
            },
            timeout=5.0,
        )
    except Exception:
        pass


# ─── 全局 HTTP 连接池（应用生命周期管理，避免 TCP 泄露）────────────────────────
_http_client: httpx.AsyncClient | None = None


@asynccontextmanager
async def lifespan(application: FastAPI):
    global _http_client
    _http_client = httpx.AsyncClient()
    yield
    await _http_client.aclose()


app = FastAPI(
    title="VPS-OPS API Gateway",
    description="统一 API 网关 v2.2 — Webhook 透传 + /ops/ 数据中台 + PushPlus 推送",
    version="2.2.0",
    lifespan=lifespan,
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
    适用于：SSE 打字机输出 / Webhook 请求体 / 任何流式场景。
    使用应用全局共享的 AsyncClient 连接池。
    """
    assert _http_client is not None, "HTTP client 未初始化"

    path = request.url.path
    if strip_prefix and path.startswith(strip_prefix):
        path = path[len(strip_prefix) :]
    if not path.startswith("/"):
        path = "/" + path
    url = f"{target_url}{path}"
    if request.url.query:
        url = f"{url}?{request.url.query}"

    headers = {k: v for k, v in request.headers.items() if k.lower() != "host"}
    body = await request.body()

    req = _http_client.build_request(request.method, url, headers=headers, content=body)

    try:
        resp = await _http_client.send(
            req,
            stream=True,
            extensions={
                "timeout": {
                    "connect": 10.0,
                    "read": timeout,
                    "write": timeout,
                    "pool": timeout,
                }
            },
        )
    except httpx.RequestError as e:
        return JSONResponse(
            status_code=502,
            content={"error": "Bad Gateway", "detail": str(e), "target": url},
        )

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
        "version": "2.2.0",
        "routes": {
            "/webhook/*": "Webhook Relay → NAS n8n (nginx-relay 内网穿透)",
            "/ops/quant/signal": "A股量化信号接收 [POST, 需 X-VPS-Token]",
            "/ops/research/paper": "科研文献元数据归档 [POST, 需 X-VPS-Token]",
            "/ops/health": "数据中台健康检查 [GET, 需 X-VPS-Token]",
            "/health": "公开健康检查 [GET]",
        },
    }


@app.get("/health", tags=["系统监控"])
async def health():
    """公开健康检查 — 供 Cloudflare / Uptime Kuma 探针使用"""
    return {"status": "ok"}


@app.api_route(
    "/webhook/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    tags=["Webhook"],
)
async def proxy_webhook(request: Request):
    """透传到 Nginx Relay → 宿主机 Tailscale → NAS n8n，超时 30s"""
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
    接收 A股量化交易信号并推送微信通知。
    外部调用：POST https://api.660415.xyz/ops/quant/signal
    Header:   X-VPS-Token: <VPS_TOKEN>
    """
    print(
        f"[量化引擎] {signal.symbol} → {signal.signal_type}"
        f"  策略: {signal.strategy_name}  价格: {signal.price}"
    )
    emoji = (
        "🟢"
        if signal.signal_type.upper() == "BUY"
        else "🔴" if signal.signal_type.upper() == "SELL" else "🟡"
    )
    await send_pushplus(
        f"{emoji} [量化] {signal.symbol} {signal.signal_type}点信号",
        f"**标的**: {signal.symbol}\n**信号**: {signal.signal_type}\n"
        f"**策略**: {signal.strategy_name}\n**价格**: {signal.price}\n"
        f"**时间**: {signal.timestamp}",
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
    接收高功率光纤激光器科研文献元数据并推送微信通知。
    外部调用：POST https://api.660415.xyz/ops/research/paper
    Header:   X-VPS-Token: <VPS_TOKEN>
    """
    # TODO: 触发 Cloudflare Pages MkDocs 重新构建
    print(f"[学术引擎] 归档: {paper.title[:40]}  标签: {paper.tags}")
    await send_pushplus(
        "📚 [学术] 新文献已归档",
        f"**标题**: {paper.title[:60]}\n**标签**: {', '.join(paper.tags)}\n"
        f"**归档时间**: {paper.extraction_time}",
    )
    return {
        "status": "success",
        "message": "文献元数据已归档",
        "tags_indexed": paper.tags,
    }


@app.get("/ops/health", tags=["A股量化", "学术科研"])
async def ops_health(_: None = Depends(verify_token)):
    """受保护健康检查 — 验证 Token 是否配置正确"""
    return {"status": "ok", "role": "Data_Hub_Backend"}
