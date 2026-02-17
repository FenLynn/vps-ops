# 推荐 GitHub Skills（学术科研+物理学方向）

根据你的领域（学术写作、高功率光纤激光器、物理学），我为你精选了 GitHub 上**最热门、评价最高**的 Skills 仓库。

---

## 🔥 顶级推荐（必装）

### 1. **anthropics/skills** ⭐ 64.9k stars
**GitHub**: https://github.com/anthropics/skills

**推荐理由**：
- 🏆 **Anthropic 官方 Skills 仓库**，是整个生态的"黄金标准"。
- 🎯 包含 **Document Processing（文档处理）**、**Data Analysis（数据分析）**、**Communication & Writing（写作与沟通）** 等多个分类。
- ✅ 已经过 6.4k 次 Fork 验证，质量极高。

**推荐安装的 Skills（适合你）**：
- `doc-coauthoring`：分阶段协作写作（收集上下文→头脑风暴→起草→精修→读者测试）。
- `docx`：创建、编辑、分析 Word 文档（适合期刊投稿）。
- `canvas-design`：生成论文概念图、框架图（以 design philosophy 驱动）。

---

### 2. **K-Dense-AI/claude-scientific-skills** ⭐ 热门新秀
**GitHub**: https://github.com/K-Dense-AI/claude-scientific-skills

**推荐理由**：
- 🔬 **专为科学研究设计**，包含 **140 个现成技能**。
- 📝 明确包含 **Scientific Writing（科学写作）**、**Peer Review（同行评审）**、**LaTeX Posters（学术海报）**。
- 🎯 多步骤科学工作流自动化（从文献综述到实验分析）。

**推荐安装的 Skills**：
- `scientific-writing`：专业的学术写作助手。
- `latex-poster`：快速生成学术会议海报（LaTeX 格式）。
- `peer-review`：模拟同行评审流程。

---

### 3. **K-Dense-AI/claude-scientific-writer**
**GitHub**: https://github.com/K-Dense-AI/claude-scientific-writer

**推荐理由**：
- 📄 深度研究与写作工具，专注于**生成可发表的科学论文**、报告、提案。
- ✅ 支持 **LaTeX 格式化输出**（适合物理学高质量投稿）。
- 🚀 可作为 Claude Code 插件直接在 IDE 中使用。

---

### 4. **matsengrp/plugins** ⭐ 学术 LaTeX 专用
**GitHub**: https://github.com/matsengrp/plugins

**推荐理由**：
- 📐 提供专门的 **LaTeX 编辑和语法检查 Agent**。
- ✍️ `scientific-tex-editor`：专业的 LaTeX 科学编辑。
- 🔍 `tex-grammar-checker`：LaTeX/TeX 文件的详细语法检查。

---

## 🎯 按需选装（进阶）

### 5. **Orchestra-Research/AI-Research-SKILLs** ⭐ 已安装在你的系统中
**GitHub**: https://github.com/Orchestra-Research/AI-Research-SKILLs

**推荐理由**：
- 🧪 **83 个 AI 研究工程技能**（你已经通过脚本克隆）。
- 📊 覆盖**微调、后训练、推理、评估、MLOps** 等全流程。

**推荐从中安装**（针对你的需求）：
- `20-ml-paper-writing`：ML 论文写作（NeurIPS / ICML / ICLR / ACL / AAAI）。
- `13-mlops/weights-and-biases`：实验跟踪与记录。
- `11-evaluation/lm-evaluation-harness`：模型评估标准化。

---

## 📊 热度对比表

| 仓库名称 | Stars | 适用场景 | 安装难度 |
|---------|-------|---------|---------|
| anthropics/skills | 64.9k ⭐⭐⭐⭐⭐ | 通用学术+企业工作流 | 简单 |
| claude-scientific-skills | 新秀 🔥 | 科学研究多步骤流程 | 简单 |
| claude-scientific-writer | 专业 📄 | 可发表论文撰写 | 中等 |
| matsengrp/plugins | 小众精品 📐 | LaTeX 专业编辑 | 简单 |
| AI-Research-SKILLs | 已安装 ✅ | AI 研究工程全流程 | 已完成 |

---

## 💡 如何安装这些 Skills？

### 方法 1：使用我的脚本（推荐）
对于 `AI-Research-SKILLs` 中的技能，直接运行：
```powershell
.\manage_orchestra_skills.ps1 -Install "20-ml-paper-writing"
```

### 方法 2：手动克隆（适合其他仓库）
```bash
# 克隆到临时目录
git clone https://github.com/anthropics/skills C:\temp\anthropic-skills

# 选择你需要的 Skill 文件夹复制到全局目录
copy C:\temp\anthropic-skills\doc-coauthoring C:\Users\lify\.gemini\antigravity\skills\
```

### 方法 3：使用 OpenSkills（一键安装）
```bash
npx openskills install anthropics/skills
```
然后在交互界面中勾选你需要的技能。

---

## 🎓 我的推荐优先级（Top 5）

1. **anthropics/skills/doc-coauthoring** → 适合多轮迭代论文写作
2. **K-Dense-AI/claude-scientific-writer** → 适合快速生成发表级手稿
3. **matsengrp/plugins/scientific-tex-editor** → 适合 LaTeX 深度编辑
4. **AI-Research-SKILLs/20-ml-paper-writing** → 适合 CS/ML 方向投稿
5. **K-Dense-AI/claude-scientific-skills/peer-review** → 适合自我审稿

---

## 🔬 光学/光纤激光器算法库（编程工具）

### 6. **pyLaserPulse** (jsfeehan/pyLaserPulse)
**GitHub**: https://github.com/jsfeehan/pyLaserPulse

**推荐理由**：
- 🔥 **专为脉冲光纤系统设计**的 Python 仿真工具箱。
- ⚡ 支持 **偏振分辨的激光脉冲传播**（非线性、色散、有源/无源光纤）。
- 🧮 包含 **广义非线性薛定谔方程 (GNLSE) 求解器**。
- 🎯 快速原型设计光纤激光器和放大器系统。

**适用场景**：
- 模拟 TMI（横向模式不稳定性）的动态演化
- 脉冲传播中的非线性效应（SPM、XPM、FWM）
- 色散管理和啁啾脉冲放大

---

### 7. **PyFiberAmp** (Jomiri/pyfiberamp)
**GitHub**: https://github.com/Jomiri/pyfiberamp

**推荐理由**：
- 🔧 **稀土掺杂光纤放大器/激光器**的速率方程仿真库。
- 📈 基于 Giles 模型，支持：
  - 核心泵浦和双包层光纤放大器
  - 连续波 (CW)、增益开关、Q 开关光纤激光器
  - 多泵浦/信号/ASE 通道
- 🎓 适合学术研究和工程设计。

**适用场景**：
- 高功率光纤激光器的增益和功率预测
- 泵浦优化和热效应分析
- ASE（放大自发辐射）噪声建模

---

### 8. **awesome_photonics** (joamatab/awesome_photonics)
**GitHub**: https://github.com/joamatab/awesome_photonics

**推荐理由**：
- 📚 **光子学开源工具的精选列表**（300+ stars）。
- 🔍 涵盖：
  - **NLSE 求解器**（`Laserfun`, `PyNLO`）
  - **FDTD 仿真**（`MEEP`, `fdtdx`）
  - **光线追踪**（`rayoptics`, `optiland`）
  - **模式求解器**（`femwell`, `tidy3d`）
- 🐍 绝大多数工具有 Python 接口。

**推荐子项目**：
- `diffractsim`：衍射与传播模拟
- `TorchOptics`：基于 PyTorch 的可微分光学
- `prysm`：相位恢复与光学系统分析

---

### 9. **FiberModeSolver** (TriGuez/FiberModeSolver)
**GitHub**: https://github.com/TriGuez/FiberModeSolver

**推荐理由**：
- 🔬 计算光纤的**传播模式**（有效折射率、模场分布）。
- 📐 支持多种光纤类型（单模、多模、微结构光纤）。
- 💡 包含熔融石英的折射率和损耗计算函数。

---

## 🎨 创意/有趣的 Skills（开拓视野）

### 10. **algorithmic-art** (Anthropic Skills)
**来源**: anthropics/skills

**推荐理由**：
- 🎨 使用 **p5.js** 生成算法艺术。
- 🌊 支持流场（Flow Fields）、粒子系统（Particle Systems）、种子随机性。
- 🖼️ 可用于论文/演讲的视觉化创意图形。

**用途**：
- 为论文生成独特的封面图
- 创作数据可视化的艺术化版本
- 探索混沌系统和分形结构

---

### 11. **D3.js Visualization** (Anthropic Skills)
**来源**: anthropics/skills

**推荐理由**：
- 📊 生成交互式 **D3.js 数据可视化图表**。
- 🚀 支持动态图表、网络图、时间序列可视化。
- 🌐 可直接嵌入网页或演示文稿。

**用途**：
- 实验数据的交互式展示
- 论文补充材料的动态图表
- 学术会议演讲的炫酷可视化

---

### 12. **game-developer** (Claude Code Subagent)
**来源**: Claude Code 社区

**推荐理由**：
- 🎮 专为**游戏开发**设计的 AI 助手。
- 🛠️ 支持 Unity、Unreal Engine、Godot。
- ⚙️ 包含：
  - 引擎架构设计
  - 图形编程（光照、阴影、粒子系统）
  - 多人网络同步
  - 性能优化（60 FPS、低延迟）

**有趣用途**：
- 开发物理仿真的可视化工具
- 制作激光传播的 3D 交互演示
- 创建科研数据的游戏化展示

---

### 13. **Slack GIF Creator** (Anthropic Skills)
**来源**: anthropics/skills

**推荐理由**：
- 😄 生成**自定义动画 GIF**（用于 Slack、社交媒体）。
- 🎬 可用于学术展示的动态示意图。
- 🤖 支持文字、动画、特效组合。

**创意用途**：
- 实验过程的动画展示
- TMI 阈值变化的动态演示
- 会议海报的二维码动画

---

### 14. **claude-scientific-skills/Physics & Astronomy**
**GitHub**: K-Dense-AI/claude-scientific-skills

**推荐理由**：
- 🌌 包含 **天文数据分析**、**坐标转换**、**宇宙学计算**。
- 🔭 支持符号数学（SymPy）和物理计算。
- 🚀 适合跨学科研究（光学 + 天文学）。

---

### 15. **ComputationalMaterials** (Claude Code Agent)
**来源**: Claude Code 社区

**推荐理由**：
- 🧪 **计算材料科学** Agent。
- ⚙️ 涵盖：
  - 数值稳定性分析
  - 网格生成（Mesh Generation）
  - 参数优化
  - 后处理与可视化
- 🔬 适合光纤材料的热力学仿真。

---

## 🎯 按使用场景分类速查表

| 使用场景 | 推荐 Skill/工具 | 难度 |
|---------|----------------|------|
| **光纤激光器仿真** | pyLaserPulse, PyFiberAmp | ⭐⭐⭐ |
| **脉冲传播建模** | pyLaserPulse, PyNLO | ⭐⭐⭐⭐ |
| **模式求解** | FiberModeSolver, femwell | ⭐⭐⭐ |
| **学术论文写作** | claude-scientific-writer, doc-coauthoring | ⭐⭐ |
| **LaTeX 编辑** | matsengrp/scientific-tex-editor | ⭐⭐ |
| **数据可视化** | D3.js Visualization, Matplotlib Skills | ⭐⭐ |
| **算法艺术** | algorithmic-art, canvas-design | ⭐ |
| **游戏化展示** | game-developer (Unity/Unreal) | ⭐⭐⭐⭐ |
| **同行评审模拟** | peer-review (claude-scientific-skills) | ⭐⭐ |

---

## 🚀 极客推荐（高级玩法）

### ⚡ 组合技能流（Workflow）
你可以将多个 Skills 串联使用：
1. **pyLaserPulse** 生成仿真数据 → 
2. **D3.js Visualization** 生成交互式图表 → 
3. **claude-scientific-writer** 自动写 Results 章节 → 
4. **matsengrp/scientific-tex-editor** 润色 LaTeX →
5. **peer-review** 自我审稿

### 🎨 学术 + 艺术混搭
- 用 **algorithmic-art** 创作论文封面（基于你的实验数据）
- 用 **game-developer** 制作 TMI 动态演示（3D 可视化）

---

需要我帮你安装其中某几个吗？或者你想先测试哪一个？

