# Antigravity Skills 新手使用手册 (User Manual)

欢迎使用 **Antigravity Skills**！这份手册将带你快速上手如何利用 **Skills** 扩展你的 AI 助手能力。无论是学术写作、代码微调还是日常开发，Skills 都能让你的助手变得更专业。

## 🌟 核心概念：什么是 Skill？

在 Antigravity 中，**Skill** 就是一个包含特殊指令（`SKILL.md`）的文件夹。
当你把这个文件夹放在正确的位置，你的 AI 助手就会“学会”其中的技能。

*   **Global Skills (全局技能)**：存放在 `C:\Users\lify\.gemini\antigravity\skills`。
    *   **作用范围**：所有项目通用。
    *   **适合**：常用工具（如学术写作助手、代码审查工具、通用微调脚本）。

## 📂 目录结构说明

我们将为你维护两个核心目录，请务必区分清楚：

1.  **🗄️ 仓库缓冲 (Storage)**
    *   **路径**：`C:\Users\lify\.gemini\antigravity\storage\AI-Research-SKILLs`
    *   **作用**：这里存放了从 GitHub 下载下来的 **80+ 个原始技能包**。
    *   **注意**：这里的东西 **不会** 被 AI 自动读取。你需要从这里“挑选”你想要的技能。

2.  **✅ 生效技能 (Active Skills)**
    *   **路径**：`C:\Users\lify\.gemini\antigravity\skills`
    *   **作用**：这里是 AI 的“大脑扩展区”。凡是放在这里的文件夹，AI 都能直接使用。
    *   **预装技能**：目前已经为你预装了 `ai-research-assistant`（学术写作助手）。

---

## 🛠️ 如何安装新技能 (3种方法)

### 方法一：使用管理脚本 (推荐 ⭐)

我已经为你准备了一个从缓冲库中一键安装技能的脚本。

**1. 打开终端 (Terminal)**
在 Antigravity 中打开一个新的终端窗口。

**2. 查看所有可用技能**
运行以下命令：
```powershell
C:\Users\lify\.gemini\antigravity\manage_orchestra_skills.ps1 -List
```
你会看到一个长长的列表，列出了所有可用的技能（如 `03-fine-tuning/axolotl`, `12-inference-serving/vllm` 等）。

**3. 安装指定技能**
从列表中复制你想安装的技能路径，然后运行安装命令。
例如，安装 **Axolotl 微调工具**：
```powershell
C:\Users\lify\.gemini\antigravity\manage_orchestra_skills.ps1 -Install "03-fine-tuning/axolotl"
```
脚本会自动把这个文件夹复制到你的 `Active Skills` 目录。

---

### 方法二：手动复制 (适合高手)

如果你不想用脚本，完全可以手动操作文件管理器：

1.  打开文件夹：`C:\Users\lify\.gemini\antigravity\storage\AI-Research-SKILLs`
2.  浏览并找到你想要的文件夹（比如 `01-model-architecture/litgpt`）。
3.  **复制** 整个 `litgpt` 文件夹。
4.  打开文件夹：`C:\Users\lify\.gemini\antigravity\skills`
5.  **粘贴** 进去。
6.  完成！

---

### 方法三：自己编写 Skill (进阶)

你也可以创建属于自己的 Skill：

1.  在 `C:\Users\lify\.gemini\antigravity\skills` 下新建一个文件夹（例如 `my-python-helper`）。
2.  在里面新建一个文件 `SKILL.md`。
3.  在 `SKILL.md` 里写上你的专用 Prompt（比如你公司的代码规范、特定的工作流等）。
4.  下次对话时，直接说“用 my-python-helper 帮我写代码”，AI 就会遵守你的规范。

---

## 🎓 常用技能使用指南

### 1. 学术写作助手 (ai-research-assistant)

这是我为你**独家定制**的技能，汇集了顶会审稿人的视角和专业润色能力。

*   **润色英文**：
    > "帮我润色这段 Abstract，要求符合 ICML 风格。"
*   **中翻英**：
    > "把这段中文翻译成学术英语。"
*   **去 AI 味**：
    > "这段话它是 GPT 写的，帮我去掉 AI 味，改写得像人类。"
*   **逻辑检查**：
    > "检查一下这段 Introduction 的逻辑有没有漏洞。"
*   **模拟审稿**：
    > "假设你是 NeurIPS 的审稿人，给这篇论文提提意见（附上PDF或文本）。"

### 2. 微调/训练工具 (需通过脚本安装)

如果你通过脚本安装了 `axolotl` 或 `llama-factory` 等技能：

*   **生成配置**：
    > "用 axolotl 帮我生成一个 Llama-3 的微调配置文件。"
*   **解释参数**：
    > "axolotl 里的 load_in_4bit 参数是什么意思？"

---

## ❓ 常见问题 (FAQ)

**Q: 安装了技能后，AI 还是说不会怎么办？**
A: 尝试告诉 AI：“请重新加载 Global Skills” 或者在 Promt 里明确提到技能的名字（例如“使用 axolotl skill...”）。

**Q: 为什么不一次性把 80 个技能都装上？**
A: 技能太多会干扰 AI 的注意力，也会消耗更多的 Token（上下文窗口）。**按需安装** 是最明智的选择。

**Q: Storage 文件夹在哪里？**
A: `C:\Users\lify\.gemini\antigravity\storage\AI-Research-SKILLs`

**Q: Active Skills 文件夹在哪里？**
A: `C:\Users\lify\.gemini\antigravity\skills`
