# 排错手册

按「现象 → 原因 → 处理」组织。遇到新问题就往下加一条，别忘了写清楚当时的版本。

记录模板：

```
### 现象
（报错原文，别只写「失败」）

### 环境
node -v / npm -v / pnpm -v / dsh-tui version

### 原因
（查到的真实原因，而不是猜测）

### 处理
（实际生效的那条命令）
```

---

## 1. pacman：`filesystem conflict` / `exists in filesystem`

**现象**

```
error: failed to commit transaction (conflicting files)
npm: /usr/lib/node_modules/npm/ exists in filesystem
Errors occurred, no packages were upgraded.
```

**原因**

目录已经存在，但 pacman 数据库里没有这些文件的归属记录（旧版 `nodejs` 曾内置 npm，或曾用 npm 自身方式升级过）。pacman 不覆盖无主文件。

**处理**

```bash
pacman -Qo /usr/lib/node_modules/npm        # 确认无主
sudo mv /usr/lib/node_modules/npm /usr/lib/node_modules/npm.backup
sudo pacman -S npm
hash -r
npm -v
```

或者让 pacman 直接接管（文件内容一般是同一个 npm，风险更低）：

```bash
sudo pacman -S --overwrite '/usr/lib/node_modules/npm/*' npm
```

**注意**：`--overwrite` 的通配符要加引号。确认新装正常后再删 `npm.backup`。

---

## 2. `command not found: dsh-tui`（但明明装上了）

**现象**：`npm list -g --depth=0` 能看到包，敲 `dsh-tui` 却提示找不到命令。

**原因**：npm 全局 bin 目录不在 PATH 里。

**处理**

```bash
npm config get prefix        # 例如 /home/you/.local
ls "$(npm config get prefix)/bin"   # 应该能看到 dsh、dsh-tui、dst
```

把这个 bin 目录加进 PATH：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
exec $SHELL -l               # 或重新打开 Kitty 标签页
hash -r
```

**另一个常见原因**：刚 `pacman -S` 装完命令，当前 shell 缓存了旧的路径表 —— `hash -r` 即可。

---

## 3. `npm install -g` 报 `EACCES: permission denied`

**现象**：不加 sudo 装全局包失败，加 sudo 又引出第 1 条冲突。

**原因**：npm 全局前缀指向 `/usr/lib`（pacman 的地盘）。

**处理**：改用用户级前缀，永远不要 sudo 装 npm 包。

```bash
npm config set prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
npm install -g @deepseek-ai/dsh @deepseek-harness-tui/dsh-tui
```

顺手清理可能残留的 root 属主文件：

```bash
sudo chown -R "$(id -u):$(id -g)" "$HOME/.npm"
```

---

## 4. Node 版本被拒绝启动

**现象**

```
Unsupported Node version ...
requires ^22.19 || >=24
```

**原因**：dsh-TUI 要求 Node `^22.19 || >=24`，明确**不支持 Node 23**，也不支持预发布版（`-rc` / `-nightly`）。

**处理**

```bash
node -v
which node          # 确认用的是 /usr/bin/node 还是 nvm 的版本
sudo pacman -S nodejs   # Arch 官方现在是 26.x，天然满足 >=24
```

用 nvm / fnm 的话，切到 24 或 26：`nvm install 26 && nvm alias default 26`。

---

## 5. `ERR_PNPM_IGNORED_BUILDS`（首次启动初始化 profile 时报）

**现象**：`dsh-tui` 第一次启动，正在装 profile 依赖时 pnpm 报这个错。

**原因**：pnpm ≥11 默认阻止带 install script 的依赖执行构建脚本。

**处理**：官方说明是 dsh-TUI 的 `/update` 和 `dsh-tui update` 会自动把需要的设置写好；先试：

```bash
dsh-tui update
```

仍然失败时，检查 profile 目录并重新初始化：

```bash
ls ~/.dsh/profiles/dsh-tui
dsh-tui safe            # 只读诊断，会给出修复建议
```

极端情况下重建：`dsh-tui safe --rescue`（会构建一个干净的救援 profile）。

---

## 6. 启动卡住 / 白屏 / 直接退出

按顺序试：

```bash
dsh-tui doctor          # 环境体检
dsh-tui safe            # 只读诊断，不加载插件
dsh-tui --dump-config   # 看最终生效的配置
```

- 上次会话把界面搞坏了：换个会话启动 `dsh-tui --resume <id>`，或直接 `dsh-tui` 开新会话。
- 刚换了模型/供应商之后崩：`/provider` 配置有问题时可以在启动后立刻 `/model` 换回去。
- 看日志：`~/.dsh-tui/restart.log`、`~/.dsh-tui/settings.json`。

---

## 7. 终端里中文/框线错位

**现象**：表格、进度条、框线歪掉。

**原因**：终端字体不是等宽的中英混排字体，或 `LANG` 没设成 UTF-8。

**处理**

```bash
locale                 # 应该有 zh_CN.UTF-8 或 en_US.UTF-8
localectl set-locale LANG=zh_CN.UTF-8
```

Kitty 换个等宽字体（配置 `~/.config/kitty/kitty.conf`）：

```conf
font_family      JetBrainsMono Nerd Font
disable_ligatures never
```

---

## 8. Kitty 里任务完成没有通知

**原因**：dsh-TUI 的通知走 OSC 99（Kitty 的原生协议），需要终端支持且没被关掉。

**处理**

- 确认 `/settings` → Conversation 里 `taskNotifications` 不是 `off`。
- `notificationMethod` 用默认 `auto`；Kitty 会走 OSC 99。
- 在 tmux 里跑的话，需要 `set -g allow-passthrough on`。

---

## 9. 装包/拉依赖超时（网络问题）

**现象**：`npm install -g` 或 profile 初始化卡在下载。

**处理**：换镜像源，或给 npm 配代理。

```bash
npm config set registry https://registry.npmmirror.com   # 临时换源
npm config set proxy http://127.0.0.1:7897               # 用本地代理
npm config set https-proxy http://127.0.0.1:7897
```

git 走代理则写 `~/.gitconfig`：

```ini
[http "https://github.com"]
    proxy = http://127.0.0.1:7897
```

排错完记得把 registry 改回官方源，否则以后装到的是旧包：

```bash
npm config set registry https://registry.npmjs.org
```

---

## 10. `dsh web` 打不开 / 端口被占

```bash
dsh web                 # 会打印实际监听地址
ss -ltnp | grep node    # 看端口占用
```

只在终端用的话根本不需要 `dsh web`，直接 `dsh-tui` 即可 —— 这也是本仓库的部署目标。

---

## 11. 想重来一遍

```bash
# 只重置 TUI 设置
mv ~/.dsh-tui/settings.json ~/.dsh-tui/settings.json.bak

# 只重建 profile（保留会话与凭据）
rm -rf ~/.dsh/profiles/dsh-tui
dsh-tui

# 彻底重装（⚠️ 会连会话和凭据一起删，先备份）
mv ~/.dsh ~/.dsh.backup-$(date +%F)
npm uninstall -g @deepseek-ai/dsh @deepseek-harness-tui/dsh-tui
```
