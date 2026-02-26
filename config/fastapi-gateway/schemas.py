"""
VPS-OPS — /ops/* 路由 Pydantic 数据模型
=============================================
定义两个业务领域的严格数据契约：
  - QuantSignal：A股量化交易信号
  - ResearchPaper：高功率光纤激光器科研文献
"""

from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime


# ─── 领域 A：A股量化交易信号 ─────────────────────────────────────────────────


class QuantSignal(BaseModel):
    symbol: str = Field(..., description="股票代码，例如 sh000001", max_length=10)
    signal_type: str = Field(..., description="买卖方向: buy | sell | hold")
    strategy_name: str = Field(..., description="触发策略名称，如 MA20_Cross")
    price: float = Field(..., description="信号触发时的价格")
    timestamp: datetime = Field(
        default_factory=datetime.now, description="信号产生时间"
    )
    metadata: Optional[dict] = Field(default={}, description="附加矩阵数据或深度指标")


# ─── 领域 B：高功率光纤激光器科研文献 ───────────────────────────────────────


class ResearchPaper(BaseModel):
    title: str = Field(..., description="论文标题")
    authors: List[str] = Field(..., description="作者列表")
    abstract: str = Field(..., description="摘要内容")
    tags: List[str] = Field(
        ..., description="标签集，如 ['TMI', 'SRS', 'Saturable_Absorption']"
    )
    pdf_path: Optional[str] = Field(None, description="NAS 或 ESXi 上的物理存储路径")
    published_date: Optional[str] = Field(None, description="发表日期，如 2025-01")
    extraction_time: datetime = Field(default_factory=datetime.now)
