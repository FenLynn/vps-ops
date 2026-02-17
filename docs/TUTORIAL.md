# 📘 sci-research 全局指南 (TUTORIAL)

欢迎使用 **Sci-Research OS**。这是一个专为科研和工程研发设计的模块化操作系统框架。
本指南将带您深入了解其设计哲学、核心架构以及如何使用 "Lazy Git" 自动化工作流。

---

## 🟢 1. 设计哲学 (Philosophy)

### 1.1 为什么需要这个框架？
科研代码往往面临以下痛点：
-   **路径地狱**: 脚本在不同目录下运行，`import` 总是报错。
-   **环境混乱**: 本地是 `base`，服务器是 `py39`，导致依赖冲突。
-   **输出杂乱**: 图片、日志、临时文件混合在源码目录中。
-   **文档滞后**: 代码改了，文档没更新。

**Sci-Research OS 解决方案**:
1.  **标准化**: 统一的头部信息 (Header) 和日志记录 (Logger)。
2.  **隔离性**: 所有运行时输出强制重定向到 `temp/` 目录。
3.  **自动化**: 自动管理 Python 路径 (`router.py`)，自动更新文档 (`Lazy Git`)。

---

## 🟢 2. 核心架构深度解析 (Architecture Deep Dive)

### 2.1 Router 模式 (`router.py`)
每个子系统（如 `demo`, `lab`）都有一个 `router.py`。
-   **作用**: 它是子系统的总入口。它是唯一知道项目根目录位置的脚本。
-   **原理**: 当您运行 `demo demo_plot` 时，实际上运行的是 `router.py demo_plot`。
-   **优势**: `router.py` 会在运行具体脚本前，自动将项目根目录添加到 `sys.path`。这意味着您可以在任何脚本中直接 `import lib.xxx`，永远不用担心路径问题。

### 2.2 头部与日志 (`Header & Logger`)
-   **Header**: 每次任务启动，`lib/header.py` 会自动打印当前的用户、Python 解释器路径、Config 位置等。这对于复现实验至关重要。
-   **Logger**: `lib/logger.py` 强制将日志写入 `temp/logs/`。不再需要在代码里写 `f = open("log.txt")`。

### 2.3 临时目录 (`temp/`)
-   **设计**: 我们模仿了 Docker 的理念，将 "源码" (Source) 和 "运行时" (Runtime) 分离。
-   **规则**: 
    -   所有脚本产生的图片、数据、报告，**必须** 写入 `temp/<subsystem>/`。
    -   **好处**: 想要重置环境？只需运行 `sci clean_temp`，瞬间回到初始状态，而不影响任何代码。

---

## 🟢 3. Lazy Git 自动化工作流 (The "Lazy Git" Workflow)

## 🟢 3. Lazy Git 自动化工作流 (Git Operations Manual)

这是本框架的核心生产力工具。我们利用 Git Hooks (`prepare-commit-msg`) 连接了文档生成器，实现了"写完代码即发布"的流畅体验。

### 3.1 核心原理
当您执行 `git commit` 时，后台发生了什么？
1.  **触发 Hook**: Git 暂停提交，运行 `.githooks/prepare-commit-msg`。
2.  **更新文档**: Hook 调用 `sci doc --all`，强制更新所有 README。
3.  **自动暂存**: 将更新后的文档 (`Docs`) 自动 `git add`。
4.  **生成消息**: 分析暂存区文件，为您预填 Commit Message (如 `Feat: Update demo`)。
5.  **完成提交**: 您确认后，代码与最新文档作为一个原子操作被提交。

### 3.2 详细操作指南 (Cheatsheet)

#### ✅ 场景一：日常开发 (90% 的情况)
您修改了一些代码，想要提交：
```bash
# 1. 添加变更
git add .

# 2. 提交 (注意：不要加 -m 参数！)
git commit

# 3. (自动弹出编辑器) 确认自动生成的消息，保存并关闭。
# 4. 推送
git push
```

#### ❌ 场景二：强制手动写 Message
如果您不喜欢自动生成的消息，或者有特殊说明：
```bash
# 使用 -m 参数会跳过自动消息生成，但文档更新依然会执行
git commit -m "Fix: My custom message"
```

#### 🛠️ 场景三：初次设置 (初始化)
新环境拉取代码后，必须激活 Hook：
```bash
bin\init.bat  # Windows (也会配置 Git Hook)
# 或
bin/setup_hooks.sh
```

---

---

## 🟢 4. 快速上手 (Getting Started)

### 4.1 创建新子系统
```bash
sci create lab
# 结果: 创建 d:\work\sci-research\lab 目录，并生成 lab.bat/sh
```

### 4.2 开发新功能
```bash
# 1. 在 lab 子系统中创建草稿
lab new my_test

# 2. 编辑 lab/drafts/my_test.py
# ... 写代码 ...

# 3. 运行测试
lab my_test

# 4. 移动到 stable (成熟后)
# 手动将文件从 drafts/ 移到 stable/
```

### 4.3 清理环境
```bash
sci clean_temp
# 结果: 清空 temp/ 目录下的所有临时文件
```

---

## 🟢 5. 顶级项目标准配置

为了符合开源最高标准，我们内置了：
-   **`pyproject.toml`**: 定义项目依赖和构建工具（现代化 Python 标准）。
-   **`requirements.txt`**: 明确的依赖列表。
-   **`LICENSE`**: MIT 协议，保障您的代码权益。
-   **`.gitignore`**: 精心配置的忽略规则，杜绝垃圾文件入库。

---

> **结语**: Sci-Research OS 旨在让您专注于科研与算法本身，将工程化、文档维护和环境管理的琐事全部自动化。祝您科研顺利！🚀
