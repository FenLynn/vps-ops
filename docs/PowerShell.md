# PowerShell 使用技巧与 Linux 环境适配

本仓库推荐在 Windows 环境下使用 PowerShell 作为主力终端。为了保持与 Linux/macOS 一致的开发习惯，建议配置以下映射。

## 🚀 快速配置步骤

只需 30 秒即可完成配置：

1. **打开配置文件**：
   在 PowerShell 中直运行以下命令（若文件不存在会自动创建并用记事本打开）：
   ```powershell
   if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force }; notepad $PROFILE
   ```

2. **复制粘贴**：
   将下方的 [Linux 风格映射清单](#linux-风格映射清单-aliases) 粘贴到打开的文件末尾并保存。

3. **立即生效**：
   重启窗口，或运行：
   ```powershell
   . $PROFILE
   ```

---

## 🛠️ Linux 风格映射清单 (Aliases)

将以下代码加入你的 `$PROFILE`：

```powershell
# ==========================================
# Linux to PowerShell Migration Mappings
# ==========================================

# 1. 列表操作
# ll: 详细列表 (习惯于 ls -l)
function ll { Get-ChildItem -Force $args }
# la: 显示所有
Set-Alias la ll

# 2. 文件内容处理
# grep: 搜索文本 (底层使用 Select-String)
Set-Alias grep Select-String

# tail: 查看末尾
# 用法: tail file.log (前10行); tail -Wait file.log (持续监听)
function tail { 
    param([string]$Path, [int]$Lines = 10, [switch]$Wait) 
    if ($Wait) { Get-Content $Path -Tail $Lines -Wait } else { Get-Content $Path -Tail $Lines }
}

# head: 查看开头
function head { param([string]$Path, [int]$Lines=10) Get-Content $Path -TotalCount $Lines }

# 3. 文件系统工具
# touch: 创建空文件或更新时间戳
function touch {
    param([string]$Path)
    if (Test-Path $Path) {
        (Get-Item $Path).LastWriteTime = Get-Date
    } else {
        New-Item -ItemType File -Path $Path | Out-Null
    }
}

# which: 查找命令的物理路径
Set-Alias which Get-Command

# df: 查看磁盘挂载与空间
function df { Get-PSDrive -PSProvider FileSystem }

# 4. 其他习惯适配
Set-Alias ifconfig ipconfig
Set-Alias open Invoke-Item
Set-Alias history Get-History

Write-Host "✅ Linux Aliases Loaded: ll, la, grep, touch, tail, head, which, df" -ForegroundColor Cyan
```

---

## 💡 PowerShell 实用技巧

### 1. 自动补全建议 (PSReadLine)
如果你希望获得类似 `zsh-autosuggestions` 的体验（灰色历史记录预测），在 `$PROFILE` 中加入：
```powershell
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
```

### 2. 管道符的威力
PowerShell 的管道传递的是 **对象** 而不是纯字符串。
*   **筛选文件大小**：`ls | where length -gt 1mb`
*   **按修改时间排序**：`ls | sort LastWriteTime`

### 3. sudo 替代方案
推荐安装 `gsudo` (`winget install gsudo`)。
安装后你可以直接在普通窗口运行 `sudo` 命令，就像 Linux 一样。

### 4. 默认已有的别名
PowerShell 默认已经内置了以下别名，你无需手动设置：
* `ls` -> `Get-ChildItem`
* `cp` -> `Copy-Item`
* `mv` -> `Move-Item`
* `rm` -> `Remove-Item`
* `cat` -> `Get-Content`
* `ps` -> `Get-Process`

---

## 🐍 在 PowerShell 中配置 Conda 环境

## 🐍 Anaconda/Miniconda 环境配置终极指南

本指南旨在帮助你在新电脑上以**最快、最稳妥**的方式配置 PowerShell 的 Conda 环境，涵盖了标准流程以及针对**中文系统路径**的避坑方案。

### 1. 核心原理
Conda 需要两步才能在 PowerShell 中正常工作：
1. **环境变量**：让系统能找到 `conda.exe` 和 Python 核心库 (DLLs)。
2. **Shell Hook**：在 PowerShell 启动通过 `$PROFILE` 加载钩子，接管 `activate` 命令。

### 2. 标准配置流程 (三步走)

请按顺序操作，每一步都至关重要。

#### 第一步：配置环境变量 (最常见报错源)
无论是安装在 C 盘还是 E 盘，必须将以下 **3 个路径**添加到系统的 `Path` 环境变量中（缺一不可）：

*(假设安装路径为 `E:\ProgramData\Anaconda3`)*
```text
E:\ProgramData\Anaconda3
E:\ProgramData\Anaconda3\Scripts
E:\ProgramData\Anaconda3\Library\bin
```
> **⚠️ 警告**：如果不加 `Library\bin`，直接运行 Python 会因为找不到 OpenSSL/DLL 而报错。

#### 第二步：解锁脚本权限
默认情况下 PowerShell 禁止运行配置文件。请**以管理员身份**打开 PowerShell，运行：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
遇到提示输入 `A` 或 `Y` 确认。

#### 第三步：注入配置钩子 (二选一)

**方案 A：自动配置 (推荐英文系统)**
以管理员身份运行：
```powershell
conda init powershell
```
如果提示 "modified ... profile.ps1"，说明成功。重启 PowerShell 即可。

**方案 B：手动配置 (推荐中文系统/路径乱码)**
如果你的文档路径包含中文（如 `D:\文档`），自动命令通常会失效（因为乱码导致写错文件）。
**最稳妥的办法是手动创建配置文件**：

1. 打开你的**文档**文件夹 (例如 `D:\文档` 或 `C:\Users\YourName\Documents`)。
2. 进入 `WindowsPowerShell` 文件夹（如果没有，手动新建一个）。
3. 新建一个文本文件，重命名为 **`Microsoft.PowerShell_profile.ps1`** (注意后缀名修改)。
4. 右键编辑，粘贴以下内容并保存：

```powershell
#region conda initialize
# !! Contents within this block are managed by 'conda init' !!
# 下面的路径要改成你实际的安装路径
(& "E:\ProgramData\Anaconda3\Scripts\conda.exe" "shell.powershell" "hook") | Out-String | Invoke-Expression
#endregion
```

---

### 3. 日常使用技巧

#### 验证环境
重启 PowerShell，你应该能看到命令行前面出现了 `(base)`。
```powershell
conda activate py  # 切换环境
```

#### 关闭默认 Base 环境
如果你不希望打开终端就自动进入 `(base)`，可以运行：
```powershell
conda config --set auto_activate_base false
```
设置后，默认环境为空，需要时手动 `conda activate [env]` 即可。

### 4. 常见问题排查 (Troubleshooting)

*   **Q: 输入 `conda` 提示找不到命令？**
    *   **A**: 检查**第一步**，必须确保三个路径都已正确添加到环境变量，并且重启了终端。
*   **Q: 输入 `conda activate` 报错 `CommandNotFoundError`？**
    *   **A**: 说明**第三步**没配置好。Powershell 没有加载钩子。请使用**方案 B** 手动检查文件内容。
*   **Q: 打开 PowerShell 提示“无法加载文件...因为在此系统上禁止运行脚本”？**
    *   **A**: 说明**第二步**没做。运行 `Set-ExecutionPolicy RemoteSigned`。
*   **Q: 运行 Python 报错 DLL load failed？**
    *   **A**: 说明环境变量漏了 `Library\bin`。
