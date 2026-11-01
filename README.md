# Arch Linux 部署 DeepSeek Harness（DSH）+ DSH-TUI

> 目标：在 **Arch Linux + Kitty** 里用纯终端（不依赖浏览器 Web UI）运行 DeepSeek Harness。
> 本仓库是个人安装手册，记录**每条命令的作用**、**踩过的坑**，以及**哪些步骤已经核对、哪些还没实测**。

## 状态标记

| 标记 | 含义 |
| --- | --- |
| ✅ | 本次已核对官方文档 / 官方软件源，可以直接照做 |
| ⏳ | 尚未在你的 Arch 上实测，跑完请回填结果 |

核对日期：2026-11-01。升级前请以官方文档为准。

---

## 1. 目标环境

| 项目 | 配置 |
| --- | --- |
| 操作系统 | Arch Linux |
| 桌面环境 | GNOME |
| 显示协议 | X11 |
| 终端 | Kitty |
| 运行时 | Node.js（Arch 官方 `nodejs` 包） |
| 包管理 | pacman / npm / pnpm |
| AI 框架 | DeepSeek Harness（`@deepseek-ai/dsh`） |
| 终端界面 | DSH-TUI（`@deepseek-harness-tui/dsh-tui`，社区项目） |

先分清两个东西，很容易搞混：

- `@deepseek-ai/dsh` —— **官方 CLI**，提供 `dsh` 命令（启动 profile、管理插件、`dsh web` 浏览器界面）。
- `@deepseek-harness-tui/dsh-tui` —— **社区终端界面**，安装后提供 `dsh-tui` 和 `dst` 命令。

`dsh-tui` 是终端聊天界面；`dsh web` 打开的是浏览器 Web UI，两者不是一回事。

---

## 2. 最小路径（TL;DR）

```bash
# 1) 系统与依赖（pnpm 在 Arch 官方源里就有，不要用 npm 全局装）
sudo pacman -Syu
sudo pacman -S nodejs npm pnpm git

# 2) 全局安装 CLI + 终端界面（不要用 sudo）
npm install -g @deepseek-ai/dsh @deepseek-harness-tui/dsh-tui

# 3) 配置密钥（详见第 7 节）
export DEEPSEEK_API_KEY="sk-..."

# 4) 启动
dsh-tui
```

第一次启动会自动初始化 `~/.dsh/profiles/dsh-tui`，需要 pnpm 在 PATH 里。

下面的章节解释「为什么」，以及「出问题怎么办」。

---

## 3. 装之前先知道的三个坑

1. **不要 `sudo npm install -g`。**
   以 root 身份装全局包会把文件写进 `/usr/lib/node_modules`，和 pacman 抢地盘，之后升级 `nodejs` / `npm` 就会报文件冲突。改用用户级前缀（见步骤 4）。

2. **`dsh-tui` 首次启动需要 pnpm。**
   它会在 `~/.dsh/profiles/dsh-tui` 里创建 profile 并装依赖；没有 pnpm 会直接失败。

3. **Node 版本要求 `^22.19 || >=24`，Node 23 和预发布版会被拒绝启动。**
   Arch 官方 `nodejs` 目前是 26.x，满足要求；如果你用 nvm 之类的版本管理器，注意别停在 23 或 rc 版本上。

---

## 4. 步骤一：系统更新与基础依赖 ✅

Arch 用 pacman 管理软件包。先更新系统（Arch 是滚动发行版，不支持部分升级）：

```bash
sudo pacman -Syu
```

安装 Node.js、npm 和 pnpm：

```bash
sudo pacman -S nodejs npm pnpm git
```

本次核对的官方源版本（2026-11-01，`extra` 仓库）：

| 包 | 版本 | 说明 |
| --- | --- | --- |
| `extra/nodejs` | 26.13.0-1 | V8 JavaScript 运行时（Current） |
| `extra/npm` | 12.2.1-1 | JavaScript 包管理器 |
| `extra/pnpm` | 12.16.1-1 | 快速、省磁盘的包管理器 |

验证：

```bash
node -v    # 期望 v26.x（只要 >=24 即可）
npm -v
pnpm -v
```

> 本次安装记录里 `node -v` 显示 `v26.13.0`，与官方源版本一致 ✅
>
> 小知识：`nodejs` 包把 npm 列为**可选依赖**，所以只装 `nodejs` 不会自动带上 npm，必须显式装 `npm`。

---

## 5. 步骤二：处理 `filesystem conflict`（npm 装不上时看这里）⏳

### 现象

装 npm 时 pacman 中断：

```
error: failed to commit transaction (conflicting files)
npm: /usr/lib/node_modules/npm/ exists in filesystem
Errors occurred, no packages were upgraded.
```

### 原因

目录 `/usr/lib/node_modules/npm` **已经存在**，但 pacman 的数据库里没有这些文件的归属记录（例如之前用 npm 自带的升级方式装过、或旧版 `nodejs` 曾内置 npm）。pacman 不愿意覆盖无主的文件，于是拒绝安装。

### 先诊断

```bash
pacman -Qo /usr/lib/node_modules/npm      # 谁拥有它？报 "No package owns" 就是无主
pacman -Q nodejs npm                      # npm 是否已登记；报 "package 'npm' was not found" 就是没登记
ls -la /usr/lib/node_modules/
```

### 修复 A（推荐：保留文件，让 pacman 接管）

```bash
sudo pacman -S --overwrite '/usr/lib/node_modules/npm/*' npm
```

`--overwrite` 后面跟的是**匹配文件路径的通配符**，必须加引号，避免被 shell 提前展开。

### 修复 B（保守：先备份再重装）

```bash
sudo mv /usr/lib/node_modules/npm /usr/lib/node_modules/npm.backup
sudo pacman -S npm
```

### 收尾验证

```bash
hash -r        # 清掉 shell 的命令路径缓存（bash 专用；zsh 用 rehash）
npm -v
npx -v
```

> 确认一切正常之后再删 `npm.backup`。留着它不影响使用，`/usr/lib` 下多一个目录而已。

---

## 6. 步骤三：安装 DSH 与 DSH-TUI ⏳

### 6.1 先解决「全局安装装到哪」的问题

直接 `sudo npm install -g` 是最常见的错误来源。推荐把全局前缀改到用户目录：

```bash
npm config set prefix "$HOME/.local"
```

然后把 `~/.local/bin` 加进 PATH（写进 `~/.bashrc` 或 `~/.zshrc`，GNOME 下改完要重新登录终端）：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

> 如果你更习惯 pnpm，可以 `pnpm setup` 之后用
> `pnpm add -g @deepseek-ai/dsh @deepseek-harness-tui/dsh-tui`，
> 效果一样，可执行文件都在 `PNPM_HOME` 里。

### 6.2 一条命令装两个包

```bash
npm install -g @deepseek-ai/dsh @deepseek-harness-tui/dsh-tui
```

也可以分开装、分别验证（排查问题时更好定位）：

```bash
npm install -g @deepseek-ai/dsh              # 官方 CLI，提供 dsh
npm install -g @deepseek-harness-tui/dsh-tui # 终端界面，提供 dsh-tui / dst
```

### 6.3 验证

```bash
dsh --help
dsh-tui version
dsh-tui doctor     # 官方自带的环境体检，会检查 Node 版本、profile 等
```

`dsh-tui doctor` 是最省事的一步，能提前发现 Node 版本不匹配、profile 缺失之类的问题。

---

## 7. 步骤四：配置 DeepSeek 密钥 ⏳

两条路，选一条：

### 路 A：TUI 内交互式配置（推荐）

启动之后在界面里用：

```
/provider          # 添加供应商 / API Key，会把它存进 DSH 的凭据存储
/auth login deepseek-account   # DSH 0.2.0-rc.1+ 也可以用账号登录方式
```

这条路不用把密钥写进任何文件，也不会被 git 捞到。

### 路 B：环境变量

`deepseek-official` 这个 API-Key 路由读取 `DEEPSEEK_API_KEY`：

```bash
export DEEPSEEK_API_KEY="sk-你的密钥"
dsh-tui
```

想持久化就写进 shell 配置：

```bash
echo 'export DEEPSEEK_API_KEY="sk-你的密钥"' >> ~/.bashrc
```

> ⚠️ 两个提醒：
> 1. 写进 `~/.bashrc` 等于明文躺在磁盘上，并且**任何**在你账号下运行的程序都能读到。共享机器建议用路 A。
> 2. 早先的草稿里写过「把 key 放进 `~/.dsh/.env`」，我**没能确认** DSH 会读取这个文件，所以本文不把它列为可用方法；以 `dsh --help` 和 `/provider` 的实际行为为准。

---

## 8. 步骤五：启动与日常使用 ⏳

```bash
dsh-tui          # 启动终端界面（首次会自动初始化 profile）
dst              # 同一个程序的短别名
dsh-tui --resume # 恢复最近一次会话；也可以 dsh-tui --resume <session-id>
dsh-tui -c       # 等价于 --continue，继续上次会话
```

`dsh-tui` 与 `dsh --profile dsh-tui` **完全等价**，前者只是封装了后者。

如果你想手动建 profile（自动初始化失败时用）：

```bash
dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui
dsh --profile dsh-tui
```

界面里常用的几个：

| 操作 | 说明 |
| --- | --- |
| `/provider` | 添加供应商、切模型 |
| `/model` | 换模型 |
| `/resume` | 会话管理器，挑历史会话 |
| `/new` | 新建会话 |
| `/compact` | 压缩上下文 |
| `/settings` | TUI 设置（存在 `~/.dsh-tui/settings.json`） |
| `/update` | 升级 dsh-TUI 并重启 |

---

## 9. 常用命令速查

| 命令 | 用途 |
| --- | --- |
| `node -v` / `npm -v` / `pnpm -v` | 查版本 |
| `pacman -Qo <路径>` | 查某个文件属于哪个包 |
| `pacman -Q nodejs npm pnpm` | 确认包是否已登记 |
| `hash -r` | 清 shell 命令缓存（装完新命令却找不到时用） |
| `npm config get prefix` | 看全局安装装到哪 |
| `npm list -g --depth=0` | 看装了哪些全局包 |
| `dsh --help` | DSH CLI 帮助 |
| `dsh web` | 打开浏览器 Web UI（不是终端界面） |
| `dsh-tui` / `dst` | 启动终端界面 |
| `dsh-tui --resume [id]` | 恢复会话 |
| `dsh-tui doctor` | 环境体检 |
| `dsh-tui safe` | 只读诊断，启动失败时的救命命令 |
| `dsh-tui update` | 升级 dsh-TUI |
| `dsh-tui migrate` | 从 Claude Code / Codex 等导入历史会话 |

---

## 10. 安全：哪些东西绝对不能提交

- API Key、任何 `.env`
- `~/.dsh/`（凭据、会话记录）
- `~/.dsh-tui/`（设置、扩展授权）
- `.credentials.yaml`
- 个人聊天记录

本仓库的 `.gitignore` 已经覆盖这些路径。提交前习惯性 `git status` 看一眼。

---

## 11. 参考链接

- DeepSeek Harness 官方仓库：<https://github.com/deepseek-ai/deepseek-harness>
- DSH-TUI 社区项目：<https://github.com/ccch1mneyyy/dsh-TUI>
- `@deepseek-ai/dsh`：<https://www.npmjs.com/package/@deepseek-ai/dsh>
- `@deepseek-harness-tui/dsh-tui`：<https://www.npmjs.com/package/@deepseek-harness-tui/dsh-tui>
- Arch `nodejs`：<https://archlinux.org/packages/extra/x86_64/nodejs/>
- Arch `npm`：<https://archlinux.org/packages/extra/any/npm/>
- Arch `pnpm`：<https://archlinux.org/packages/extra/x86_64/pnpm/>
- Arch Wiki Node.js：<https://wiki.archlinux.org/title/Node.js>
- Node.js：<https://nodejs.org/>

---

## 12. 待验证清单（跑完请回来打勾）

- [ ] `node -v` 输出 ≥ v24（记录实际值：`__________`）
- [ ] `npm -v`、`pnpm -v` 正常
- [ ] `npm install -g @deepseek-ai/dsh` 成功
- [ ] `npm install -g @deepseek-harness-tui/dsh-tui` 成功
- [ ] `dsh --help` 正常输出
- [ ] `dsh-tui doctor` 全绿
- [ ] `dsh-tui` 首次启动、能发一条消息并收到回复
- [ ] `dsh-tui --resume` 能恢复上一次会话
- [ ] Kitty 里显示正常（中文宽度、图片、任务完成通知）
- [ ] 把上面任一步的报错补进 [troubleshooting.md](troubleshooting.md)

---

## 附：仓库结构

```
arch-dsh-Deployment/
├── README.md            # 本文件：主线安装流程
├── install.sh           # 把步骤 4~6 脚本化（不碰密钥）
├── troubleshooting.md   # 报错 → 原因 → 处理
└── .gitignore           # 防止凭据误提交
```
