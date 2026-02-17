# 🐙 Git 全攻略：以 sci-research 为例

这份文档是为您量身定制的 Git 操作指南。我们将结合 `sci-research` 仓库的实际结构，用最通俗的语言解释 Git 的魔法，并教您如何完全依赖 VS Code 图形界面完成专家级的操作。

---

## 1. 🔗 连接 GitHub (初始化与 SSH)

在一切开始之前，我们需要打通本地电脑与 GitHub 云端的"秘密通道"。

### 1.1 配置 SSH Key (永久免密)
SSH Key 就像是您电脑的"指纹"。把这个指纹录入 GitHub，以后操作就不需要输密码了。

1.  **生成本地钥匙**:
    打开终端 (Terminal)，输入：
    ```bash
    ssh-keygen -t ed25519 -C "your_email@example.com"
    ```
    一直按回车（Enter），直到结束。这会在 `C:\Users\YourName\.ssh\` 下生成 `id_ed25519.pub`。

2.  **告诉 GitHub**:
    - 用记事本打开 `id_ed25519.pub`，复制里面的全部内容（以 `ssh-ed25519` 开头）。
    - 登录 GitHub -> 头像 -> **Settings** -> **SSH and GPG keys** -> **New SSH key**。
    - 粘贴进去，点击 **Add SSH key**。

### 1.2 关联仓库 (本仓库实战)
如果您是新建的文件夹：
```bash
# 1. 初始化 (在当前文件夹创建 .git 目录)
git init

# 2. 告诉 Git 咱们的云端地址在哪 (Remote)
git remote add origin https://github.com/FenLynn/sci-research.git
# 或者 (推荐 SSH 方式)
git remote add origin git@github.com:FenLynn/sci-research.git
```
*(注：如果您是用 VS Code 的 "Publish to GitHub" 按钮，这些它都自动帮您做好了)*

---

## 2. 🧠 吉特 (Git) 的大脑结构

Git 并不复杂，它其实就是三个"盘子"：

| 盘子 | 英文 | 状态 | 您的操作 |
| :--- | :--- | :--- | :--- |
| **工作区** | Working Dir | 📝 **已修改** (Modified) | 您正在写代码的地方 (`d:\work\sci-research`) |
| **暂存区** | Staging Area | 📦 **已暂存** (Staged) | 点了 VS Code 里的 `+` 号 (准备提交的包裹) |
| **仓库** | Repository | 🔒 **已提交** (Committed) | 点了 VS Code 里的 `✔` 号 (永久存档) |

### 本仓库的文件结构
在 `d:\work\sci-research` 下，有一个隐藏文件夹 `.git`，所有的历史记录都在这里。
- **千万不要手动修改 `.git` 文件夹里的内容**，除非您知道自己在做什么。
- **`.gitignore`**: 这个文件是 Git 的"黑名单"。在这个仓库里，我们配置了忽略 `temp/`, `__pycache__/`, `.vscode/` 等，确保云端永远干干净净，只有代码。

---

## 3. 🪄 本仓库的特殊魔法 (Hooks)

`sci-research` 不仅仅是一个普通的 Git 仓库，它配置了 **Git Hooks (钩子)**。
无论是您的论文项目 (`paper scigit`) 还是通用 Python 项目 (`scigit`)，只要经过初始化，都能获得以下黑科技：

### 📍 位置：`.githooks/`
我们改写了 Git 的默认行为。

### 🤖 自动化流程 (Lazy Git)
当您点击 **提交 (Commit)** 时，发生了什么？
1.  **拦截**: Git 准备提交，但被我们的 `prepare-commit-msg` 钩子拦下。
2.  **执行**: 钩子偷偷运行了 `sci doc --all`。
3.  **更新**: 
    - **系统级**: `sci doc` 重新生成全局 README。
    - **论文级**: `paper readme` 自动更新投稿状态表。
    - **项目级**: 通用项目自动检查文档更新。
4.  **打包**: 新生成的文档被自动塞进本次提交的"包裹"里。
5.  **放行**: 最终提交到云端的，永远是 **"代码 + 最新文档"** 的完美组合。

- **触发关键词**: 在 VS Code 提交框输入一个单点 **`.`** (英文句点)，点提交勾勾，系统就会自动替换成规范的信息。

---

## 4. 🖱️ VS Code 图形化实战 (保姆级)

忘记复杂的命令行，我们只用鼠标。

### 4.1 🚀 发布 (First Publish)
- **场景**: 刚写好代码，第一次传 GitHub。
- **操作**: 点击左侧源代码管理图标 -> 点击大蓝按钮 **"Publish to GitHub"** -> 选择 **"Private/Public"**。

### 4.2 🔄 日常更新 (Sync Cycle)
这是您每天做最多的动作：
1.  **写代码**: 修改了 `demo.py`。
2.  **看变化**: 左侧图标会显示 `①`，表示作为一个文件变了。
3.  **写备注 (三选一)**:
    - **懒人模式**: 直接输入一个点 **`.`** (或者上面提到的任何触发词)，然后点提交。系统会自动帮您填好。
    - **纠结模式**: 在终端输入 `sci suggest`。它会生成一句漂亮的话，并**自动复制到您的剪贴板**。您回到提交框 `Ctrl+V` 粘贴即可。
    - **专家模式**: 认真手写具体的变化。
4.  **点对勾**: 点击 **"✔ 提交"** (Commit)。
5.  **点同步**: 点击蓝色的 **"Sync Changes"** (同步) 按钮，把代码推送到云端。

### 4.3 🏷️ 发行版 (Release) - **冻结时刻**
- **场景**: 代码很稳定了，我想存一个 `v1.0` 只有我能下载。
- **操作**:
    1. 去 GitHub 网页 -> **Releases**。
    2. **Draft a new release**。
    3. Tag: `v1.0` -> Title: `Release v1.0` -> **Publish**。
    4. **结果**: GitHub 生成 `Source code (zip)`，永久归档。

### 4.4 📥 拉取 (Pull) - **多端同步**
- **场景**: 您在家里电脑更新了代码，到了办公室发现代码还是旧的。
- **操作**: VS Code 左下角如果不转圈，点一下那个 **循环箭头** 图标 (Synchronize)。它会自动把云端最新的代码拉下来。

### 4.5 🔙 回退 (Undo) - **后悔药**
- **场景**: 刚才提交的代码写的太烂了，我想撤销。
- **操作**:
    1. 在 VS Code 左侧源代码管理面板，点击右上角 **... (更多)**。
    2. 选择 **Commit (提交)** -> **Undo Last Commit (撤销上次提交)**。
    3. **结果**: 刚才提交的代码变回了"暂存"状态，您可以修改后再提交。

### 4.6 🌿 分支 (Branch) - **平行宇宙**
- **场景**: 我想试一个疯狂的新功能，但怕把现在的代码搞坏。
- **操作**:
    1. 点击 VS Code 左下角的 `main` (当前分支名)。
    2. 在弹出的菜单选 **"Create new branch..."**。
    3. 输入名字 `feature-x`。
    4. 现在您就在平行宇宙了！随便改代码，不会影响 `main`。
    5. 改满意了？切回 `main`，然后把 `feature-x` **Merge (合并)** 过来 (通常在 GitHub 网页上发 Pull Request)。

### 4.7 🧹 清理“黑历史” (合并提交)
- **场景**: 刚才为了测试功能，连续提交了 5-6 次，全是 "auto", ".", "test" 这样的烂注释，想在同步到云端前把它们合并成一个完美的提交。
- **操作 (终极方案)**:
    1. 打开终端，输入：
       ```bash
       git reset --soft origin/main
       ```
    2. **发生了什么？**: 所有的本地新提交都会被“撤销”，但您写的所有代码**仍然保留**在“暂存区”（左侧是绿色的 `+` 状态）。
    3. **重新提交**: 在提交框里输入一个点 **`.`**，点对勾提交。
    4. **结果**: 之前的 6 次乱象统统消失，变成了一个由钩子生成的、工整的提交记录。

---

## 5. 🛡️ 最佳实践

1.  **勤提交**: 不要写了一周才提交一次。每完成一个小功能就提交一次 (Commit)，这样"后悔药"的颗粒度更细。
2.  **多同步**: 每天下班前点一次 Sync，确保云端有备份。硬盘坏了也不怕。
3.  **看状态**: VS Code 左侧的文件颜色很有用：
    - <span style="color:green">绿色 (U)</span>: 新文件 (Untracked)
    - <span style="color:orange">黄色 (M)</span>: 修改过 (Modified)
    - <span style="color:red">红色 (D)</span>: 已删除 (Deleted)

希望这份指南能成为您科研路上的瑞士军刀！🛠️

---

## 6. 🌍 多机协作与新电脑配置 (新手必读)

当您在另一台电脑（如实验室台式机）上工作时，如何保持和主机完全一致的"丝滑体验"（`.` 自动提交、自动生成文档）？既然是中心化管理，我们就要利用 Git 的高级特性来实现**"一次配置，处处生效"**。

### 6.1 原理：为什么以前不用配，现在要配？
您可能会问："为什么旧电脑不用输命令，新电脑的每个新仓库（如 `matlab`）都要输一句 `git config ...`？"

这包含两个核心机制：
1.  **安全机制 (Security)**: Git 默认**不会**因为你把项目下载下来就自动执行里面的脚本。这是为了防止黑客在仓库里埋雷。所以，您必须**主动**输入命令，明确告诉 Git："我信任这个仓库里的脚本，请启用它"。
2.  **复用机制 (Central Kitchen)**: 
    *   `D:\work\sci-research` 就像是您的**"中央厨房"**。
    *   您的 `matlab`、`project_a` 等仓库，不需要各自复制一份脚本。
    *   只需运行命令，相当于**"接一根管子"**到中央厨房。
    *   **好处**: 以后只要更新了中央厨房的脚本，所有连接的仓库都会自动享受到最新功能！

### 6.2 第一阶段：基础环境复刻 (仅需一次)
在新电脑上，尽量保持盘符和路径一致（`D:\work\sci-research`），这样最省心。

#### 1. 身份配置 (Identity)
为了在 GitHub 的贡献图（绿格子）上正确统计，同时区分已提交的来源：
*   **邮箱 (Email)**: **必须保持一致！** 这是识别身份的唯一凭证。
*   **用户名 (Name)**: **推荐修改！** 可以加后缀区分设备，方便看 Log。

```powershell
# 在新电脑的 PowerShell 运行：
git config --global user.email "your_email@example.com"  # 保持一致
git config --global user.name "Your Name (Lab)"         # 区分设备
```

#### 2. 习惯同步 (Global Config)
让基础行为一致：
```powershell
git config --global core.autocrlf true        # 自动处理换行
git config --global core.quotepath false      # 显示中文文件名
git config --global core.symlinks true        # 开启软链接 (Paper系统必需)
git config --global credential.helper store   # 记住密码(免去反复输)
```

#### 3. 环境变量 (System Path)
把 `D:\work\sci-research\bin` 加入系统的 `Path` 环境变量。这样您就能在任意位置敲 `sci` 和 `paper` 命令了。

---

### 6.3 第二阶段：为新仓库注入灵魂 (每个仓库一次)
当您在新电脑上新建或拉取了一个仓库（例如 `matlab`），只要运行这一句，它立马变身！

**操作步骤**：
1.  进入该仓库目录：`cd D:\work\matlab`
2.  **运行核心命令**：
    ```powershell
    git config core.hooksPath D:\work\sci-research\.githooks
    ```

**效果**：
*   ✅ **自动提交**: 输入 `.` 就能提交代码，不用写废话。
*   ✅ **自动文档**: 每次提交自动更新 README。
*   ✅ **统一标准**: 完全复用主机的全套流程。

只要记住：**新仓库，连管子！** (`git config core.hooksPath ...`)
