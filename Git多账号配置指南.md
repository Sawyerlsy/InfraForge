# Git 多账号配置完整指南

> 适用场景：同时使用 GitHub、Gitee、多个公司 GitLab 等多个 Git 平台，各平台账号不同

---

## 📋 账号信息

| 平台 | 邮箱 | 密钥文件 | 主机地址 |
|------|------|----------|----------|
| **GitHub** | sawyerlsy@126.com | `id_ed25519_github` | github.com |
| **Gitee** | hentianliandi@126.com | `id_ed25519_gitee` | gitee.com |
| **公司 GitLab1** | sawyerlsy@126.com | `id_ed25519_gitlab1` | （请替换为实际域名）|
| **公司 GitLab2** | laishaoya1@cmhk.com | `id_ed25519_gitlab2` | （请替换为实际域名）|

---

## 🚀 快速开始（一键配置）

### 方法一：使用自动脚本（推荐）

运行 `git-multi-account-setup.ps1` 脚本，自动完成所有配置：

1. 右键脚本 → 「使用 PowerShell 运行」
2. 等待自动生成 4 对密钥
3. 脚本会自动创建 config 文件
4. 按照提示将公钥添加到各平台

### 方法二：手动配置

详见下面的详细步骤。

---

## 📝 详细配置步骤

### 第 1 步：生成 SSH 密钥对

打开 **Git Bash** 或 **PowerShell**，依次执行以下命令：

```bash
# 1. GitHub 密钥
ssh-keygen -t ed25519 -C "sawyerlsy@126.com" -f ~/.ssh/id_ed25519_github

# 2. Gitee 密钥
ssh-keygen -t ed25519 -C "hentianliandi@126.com" -f ~/.ssh/id_ed25519_gitee

# 3. 公司 GitLab1 密钥
ssh-keygen -t ed25519 -C "sawyerlsy@126.com" -f ~/.ssh/id_ed25519_gitlab1

# 4. 公司 GitLab2 密钥
ssh-keygen -t ed25519 -C "laishaoya1@cmhk.com" -f ~/.ssh/id_ed25519_gitlab2
```

> 💡 提示：每次执行时，一路回车即可（密码可以不设，直接回车）。

执行完毕后，`~/.ssh/` 目录下会生成 8 个文件：

```
~/.ssh/
├── id_ed25519_github        # GitHub 私钥（保密！）
├── id_ed25519_github.pub    # GitHub 公钥（放到平台上）
├── id_ed25519_gitee         # Gitee 私钥
├── id_ed25519_gitee.pub     # Gitee 公钥
├── id_ed25519_gitlab1       # GitLab1 私钥
├── id_ed25519_gitlab1.pub   # GitLab1 公钥
├── id_ed25519_gitlab2       # GitLab2 私钥
└── id_ed25519_gitlab2.pub   # GitLab2 公钥
```

> ⚠️ **重要**：私钥文件（没有 `.pub` 后缀的）绝对不能泄露！公钥（`.pub`）是可以公开的。

---

### 第 2 步：配置 SSH config 文件

在 `~/.ssh/` 目录下新建一个名为 `config` 的文件（**没有后缀名**），内容如下：

```ssh-config
# ============================================================
# Git 多账号 SSH 配置文件
# ============================================================

# GitHub
Host github.com
    HostName github.com
    IdentityFile ~/.ssh/id_ed25519_github
    User git
    Port 22

# Gitee
Host gitee.com
    HostName gitee.com
    IdentityFile ~/.ssh/id_ed25519_gitee
    User git
    Port 22

# 公司 GitLab1
# ⚠️ 请将 gitlab1.example.com 替换为实际域名
Host gitlab1.example.com
    HostName gitlab1.example.com
    IdentityFile ~/.ssh/id_ed25519_gitlab1
    User git
    Port 22

# 公司 GitLab2
# ⚠️ 请将 gitlab2.example.com 替换为实际域名
Host gitlab2.example.com
    HostName gitlab2.example.com
    IdentityFile ~/.ssh/id_ed25519_gitlab2
    User git
    Port 22
```

#### config 文件说明

| 字段 | 说明 |
|------|------|
| `Host` | 别名，克隆仓库时用这个名字匹配 |
| `HostName` | 真实的域名/IP地址 |
| `IdentityFile` | 私钥文件路径 |
| `User` | 用户名，Git 统一用 `git` |
| `Port` | SSH 端口，默认 22 |

#### Windows 下设置 config 文件权限

SSH 对 config 文件权限有严格要求，需要设置为仅当前用户可读写：

```powershell
icacls $env:USERPROFILE\.ssh\config /inheritance:r /grant "$($env:USERNAME):F"
```

> 💡 注意：PowerShell 中使用 `$env:USERNAME` 而不是 `%USERNAME%`（那是 CMD 的写法）。

---

### 第 3 步：将公钥添加到各平台

#### 查看公钥内容

```bash
# 查看 GitHub 公钥
cat ~/.ssh/id_ed25519_github.pub

# 查看 Gitee 公钥
cat ~/.ssh/id_ed25519_gitee.pub

# 查看 GitLab1 公钥
cat ~/.ssh/id_ed25519_gitlab1.pub

# 查看 GitLab2 公钥
cat ~/.ssh/id_ed25519_gitlab2.pub
```

#### 各平台添加位置

| 平台 | 添加路径 |
|------|----------|
| **GitHub** | Settings → SSH and GPG keys → New SSH key |
| **Gitee** | 设置 → SSH 公钥 |
| **GitLab** | User Settings → SSH Keys |

操作步骤：
1. 复制对应平台的 `.pub` 文件内容（以 `ssh-ed25519` 开头的一整行）
2. 打开平台的 SSH Keys 设置页面
3. 粘贴公钥，起个名字（如 "Windows-PC"）
4. 点击添加

---

### 第 4 步：测试连接

```bash
# 测试 GitHub
ssh -T git@github.com

# 测试 Gitee
ssh -T git@gitee.com

# 测试公司 GitLab1（替换为实际域名）
ssh -T git@gitlab1.example.com

# 测试公司 GitLab2（替换为实际域名）
ssh -T git@gitlab2.example.com
```

成功的话会显示类似：
```
Hi username! You've successfully authenticated, but GitHub does not provide shell access.
```

如果第一次连接提示 `Are you sure you want to continue connecting?`，输入 `yes` 回车即可。

---

### 第 5 步：配置 Git 用户名和邮箱

#### 全局配置（最常用的账号）

设置全局的用户名和邮箱，默认所有项目都用这个：

```bash
git config --global user.name "你的名字"
git config --global user.email "sawyerlsy@126.com"
```

> 💡 建议把最常用的账号（比如公司主账号）设为全局。

#### 项目单独配置

对于需要使用其他账号的项目，在项目目录下单独设置（去掉 `--global`）：

```bash
# 进入项目目录
cd /path/to/project

# 设置该项目的用户名邮箱
git config user.name "你的名字"
git config user.name "hentianliandi@126.com"
```

#### 查看当前配置

```bash
# 查看全局配置
git config --global --list

# 查看当前项目配置
git config --local --list

# 查看所有配置（全局+项目）
git config --list
```

---

### 第 6 步：切换项目远程地址为 SSH

如果现有项目是 HTTPS 方式的，需要改成 SSH 方式：

```bash
# 查看当前远程地址
git remote -v

# 修改为 SSH 地址（示例）
git remote set-url origin git@github.com:username/repo.git
```

---

## ➕ 新增账号的方法

### 步骤

1. **生成新密钥**
   ```bash
   ssh-keygen -t ed25519 -C "新邮箱" -f ~/.ssh/id_ed25519_自定义名称
   ```

2. **在 config 文件中添加新配置**
   ```ssh-config
   # 新平台
   Host 新平台域名
       HostName 新平台域名
       IdentityFile ~/.ssh/id_ed25519_自定义名称
       User git
       Port 22
   ```

3. **添加公钥到新平台**
   ```bash
   cat ~/.ssh/id_ed25519_自定义名称.pub
   ```
   复制内容，添加到新平台的 SSH Keys 中。

4. **测试连接**
   ```bash
   ssh -T git@新平台域名
   ```

### 示例：新增一个 GitLab 账号

```bash
# 1. 生成密钥
ssh-keygen -t ed25519 -C "new@example.com" -f ~/.ssh/id_ed25519_gitlab3

# 2. config 中添加
# Host gitlab3.example.com
#     HostName gitlab3.example.com
#     IdentityFile ~/.ssh/id_ed25519_gitlab3
#     User git

# 3. 查看公钥并添加到平台
cat ~/.ssh/id_ed25519_gitlab3.pub

# 4. 测试
ssh -T git@gitlab3.example.com
```

---

## 🔧 常见问题

### Q1：提示 `Permission denied (publickey)`

**原因**：密钥没配对好。

**排查步骤**：
1. 确认公钥已添加到对应平台
2. 确认 config 文件中 `IdentityFile` 路径正确
3. 确认使用的是 SSH 地址（`git@xxx.com:...`），不是 HTTPS
4. 执行 `ssh -vT git@xxx.com` 查看详细调试信息

### Q2：提示 `Bad owner or permissions on ~/.ssh/config`

**原因**：config 文件权限不对。

**解决**：
```powershell
# Windows PowerShell
icacls $env:USERPROFILE\.ssh\config /inheritance:r /grant "$($env:USERNAME):F"
```

### Q3：两个账号用同一个邮箱可以吗？

**可以**。邮箱只是密钥的备注，不影响认证。同一个邮箱可以在多个平台使用不同的密钥。

### Q4：怎么知道当前项目用的是哪个账号？

```bash
# 查看当前项目的用户名邮箱
git config user.name
git config user.email

# 查看远程地址（判断用的是哪个平台）
git remote -v
```

### Q5：HTTPS 和 SSH 有什么区别？

| 对比项 | HTTPS | SSH |
|--------|-------|-----|
| 地址格式 | `https://github.com/...` | `git@github.com:...` |
| 认证方式 | 用户名密码/Token | 密钥 |
| 记忆方式 | 需要凭据管理器 | 配置一次永久生效 |
| 安全性 | 中等 | 高 |
| 多账号管理 | 麻烦 | 方便 |

### Q6：如何删除/更换密钥？

1. 在平台上删除旧的公钥
2. 本地删除密钥文件（`id_ed25519_xxx` 和 `id_ed25519_xxx.pub`）
3. 删除 config 中对应的配置
4. 按新增账号的步骤重新生成

### Q7：SSH 密钥类型有什么区别？

常见的 SSH 密钥类型对比：

| 类型 | 算法 | 密钥长度 | 安全性 | 速度 | 推荐 |
|------|------|----------|--------|------|------|
| **ssh-ed25519** | Ed25519 椭圆曲线 | 256 位 | ⭐⭐⭐⭐⭐ 高 | ⚡ 最快 | ⭐⭐⭐⭐⭐ **首选** |
| **ecdsa-sha2-nistp256** | ECDSA P-256 | 256 位 | ⭐⭐⭐⭐ 高 | ⚡ 快 | ⭐⭐⭐⭐ |
| **ecdsa-sha2-nistp384** | ECDSA P-384 | 384 位 | ⭐⭐⭐⭐⭐ 更高 | 中 | ⭐⭐⭐ |
| **ecdsa-sha2-nistp521** | ECDSA P-521 | 521 位 | ⭐⭐⭐⭐⭐ 最高 | 较慢 | ⭐⭐ |
| **ssh-rsa** | RSA | 2048/4096 位 | ⭐⭐⭐ 中 | 🐢 慢 | ⭐⭐ 不推荐 |
| **ssh-dss** | DSA | 1024 位 | ⭐ 低 | - | ❌ 已淘汰 |

**推荐使用 Ed25519**：
- 密钥最短（公钥只有一行，复制方便）
- 速度最快（加密解密比 RSA 快很多）
- 安全性高（256 位 Ed25519 ≈ 3072 位 RSA）
- 现在的标准选择

只有在非常老的系统不支持 Ed25519 时，才考虑用 RSA 4096。

---

## 📌 常用命令速查

### SSH 相关

```bash
# 生成密钥（推荐 ed25519）
ssh-keygen -t ed25519 -C "邮箱" -f ~/.ssh/密钥文件名

# 查看公钥
cat ~/.ssh/密钥文件名.pub

# 测试连接
ssh -T git@域名

# 调试连接（看详细日志）
ssh -vT git@域名
```

### Git 配置相关

```bash
# 全局配置
git config --global user.name "名字"
git config --global user.email "邮箱"

# 项目配置（在项目目录下执行）
git config user.name "名字"
git config user.email "邮箱"

# 查看配置
git config --global --list   # 全局配置
git config --local --list    # 当前项目配置
git config --list            # 所有配置（全局+项目）

# 修改远程地址
git remote set-url origin git@xxx.com:xxx.git

# 查看远程地址
git remote -v

# 添加远程仓库
git remote add origin git@xxx.com:xxx.git

# 删除远程仓库
git remote remove origin
```

### 基础操作（日常开发最常用）

```bash
# 查看状态（看哪些文件改了）
git status

# 查看修改内容
git diff              # 查看所有未暂存的修改
git diff 文件名       # 查看指定文件的修改
git diff --staged    # 查看已暂存的修改

# 添加文件到暂存区
git add 文件名        # 添加指定文件
git add .            # 添加当前目录所有修改
git add -A           # 添加所有修改（包括删除的文件）

# 提交代码
git commit -m "提交说明"
git commit -am "提交说明"   # 自动 add 所有已跟踪文件并提交
git commit --amend         # 修改上一次提交（还没 push 时用）

# 查看提交历史
git log                 # 查看提交记录
git log --oneline       # 简洁版（一行一条）
git log --graph         # 图形化显示分支
git log -n 10           # 只看最近 10 条
git log --author "名字"  # 看某人的提交
```

### 拉取与推送

```bash
# 拉取代码
git pull               # 拉取并合并（= git fetch + git merge）
git pull --rebase      # 拉取并变基（更干净的提交历史）
git fetch              # 只拉取，不合并（安全）

# 推送代码
git push               # 推送到远程
git push -u origin 分支名   # 第一次推送（设置上游）
git push -f            # 强制推送（⚠️ 慎用，会覆盖远程）
git push --force-with-lease   # 安全的强制推送（推荐）
```

### 分支操作

```bash
# 查看分支
git branch             # 查看本地分支
git branch -a          # 查看所有分支（本地+远程）
git branch -vv         # 查看分支与远程的对应关系

# 创建分支
git branch 分支名      # 创建新分支
git checkout -b 分支名  # 创建并切换到新分支
git switch -c 分支名    # 同上（新版 git 推荐用 switch）

# 切换分支
git checkout 分支名
git switch 分支名       # 新版 git 推荐

# 删除分支
git branch -d 分支名   # 删除已合并的分支
git branch -D 分支名   # 强制删除（未合并也删）

# 合并分支
git merge 分支名       # 把指定分支合并到当前分支
git merge --no-ff 分支名   # 不使用快进合并（保留合并记录）

# 变基
git rebase 分支名      # 把当前分支变基到指定分支上
git rebase -i HEAD~3   # 交互式变基（合并最近3个提交）
```

### 暂存（临时保存修改）

```bash
# 保存当前修改到暂存区
git stash
git stash save "说明"  # 带说明保存

# 查看暂存列表
git stash list

# 恢复暂存
git stash pop          # 恢复并删除暂存记录
git stash apply        # 恢复但保留暂存记录

# 删除暂存
git stash drop         # 删除最近的暂存
git stash clear        # 清空所有暂存
```

### 撤销与回退

```bash
# 撤销工作区修改（还没 add）
git checkout -- 文件名   # 恢复单个文件
git restore 文件名       # 同上（新版命令）
git checkout .          # 恢复所有文件（⚠️ 慎用）

# 撤销暂存（已经 add 了但还没 commit）
git reset HEAD 文件名    # 把文件从暂存区撤回
git restore --staged 文件名  # 同上（新版命令）

# 回退提交（已经 commit 了）
git reset --soft HEAD~1    # 回退到上一个提交，修改保留在暂存区
git reset --mixed HEAD~1   # 回退到上一个提交，修改保留在工作区（默认）
git reset --hard HEAD~1    # 回退到上一个提交，修改全部丢弃（⚠️ 危险）

# 回退到指定提交
git reset --hard 提交ID

# 用新提交撤销旧提交（安全，会生成新的 commit）
git revert 提交ID
```

### 标签（版本发布用）

```bash
# 查看标签
git tag

# 创建标签
git tag v1.0.0              # 轻量标签
git tag -a v1.0.0 -m "说明"  # 附注标签（带说明，推荐）

# 推送标签
git push origin v1.0.0      # 推送单个标签
git push --tags             # 推送所有标签

# 删除标签
git tag -d v1.0.0           # 本地删除
git push origin --delete v1.0.0  # 远程删除
```

### 其他实用命令

```bash
# 查看某个文件的修改历史
git log -p 文件名

# 查看某行代码是谁写的
git blame 文件名

# 清理未跟踪的文件
git clean -n          # 预览会删除哪些文件
git clean -f          # 删除未跟踪的文件
git clean -fd         # 删除未跟踪的文件和目录

# 临时忽略已跟踪文件的修改
git update-index --assume-unchanged 文件名   # 忽略
git update-index --no-assume-unchanged 文件名 # 取消忽略
```

### 工作流示例（日常开发）

```bash
# 1. 拉取最新代码
git pull --rebase

# 2. 创建开发分支
git switch -c feature/xxx

# 3. 写代码...

# 4. 查看修改
git status
git diff

# 5. 提交代码
git add .
git commit -m "feat: 完成xxx功能"

# 6. 推送到远程
git push -u origin feature/xxx

# 7. 合并到主分支（或提交 PR/MR）
git switch main
git pull --rebase
git merge feature/xxx
git push
```

---

## 📂 文件位置速查

| 文件 | 路径（Windows） |
|------|----------------|
| SSH 配置目录 | `C:\Users\用户名\.ssh\` |
| SSH config 文件 | `C:\Users\用户名\.ssh\config` |
| Git 全局配置 | `C:\Users\用户名\.gitconfig` |

---

*文档更新时间：2026-10-01（v2.0 新增 SSH 密钥类型对比 + Git 常用命令大全）*
