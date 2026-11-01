#!/usr/bin/env sh
# install.sh — 在 Arch Linux 上安装 DeepSeek Harness（DSH）与 DSH-TUI
#
# 用法：
#   sh install.sh           # 检查环境并安装
#   sh install.sh --check   # 只体检，不装任何东西
#
# 说明：
#   * 不写入任何 API Key。密钥用环境变量 DEEPSEEK_API_KEY，或启动后 /provider 交互配置。
#   * 全局包装到用户目录（默认 ~/.local），不需要 sudo。
#   * 幂等：重复执行只会重装/升级，不会重复改坏配置。
set -eu

DSH_PKG="@deepseek-ai/dsh"
TUI_PKG="@deepseek-harness-tui/dsh-tui"
CHECK_ONLY=0

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
install.sh — 在 Arch Linux 上安装 DSH + DSH-TUI

  sh install.sh           检查环境并安装
  sh install.sh --check   只体检，不装任何东西
  sh install.sh --help    显示本帮助
EOF
}

for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf '未知参数: %s（试试 --help）\n' "$arg" >&2; exit 2 ;;
    esac
done

# ---------- 1. 平台检查 ----------
case "$(uname -s)" in
    Linux) : ;;
    *) warn "这不是 Linux，脚本只针对 Arch Linux 写过，继续执行可能没有意义。" ;;
esac

if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" != "arch" ]; then
        warn "检测到的发行版是 '${ID:-未知}'，不是 arch；pacman 相关提示可以忽略。"
    fi
fi

if [ "$(id -u)" -eq 0 ]; then
    die "不要用 root 跑这个脚本。装全局 npm 包不需要 sudo，用 root 反而会污染 /usr/lib。"
fi

# ---------- 2. 发行版依赖 ----------
if command -v pacman >/dev/null 2>&1; then
    missing=""
    for p in nodejs npm pnpm git; do
        pacman -Qq "$p" >/dev/null 2>&1 || missing="$missing $p"
    done
    if [ -n "$missing" ]; then
        info "缺少 pacman 包:$missing"
        if [ "$CHECK_ONLY" -eq 1 ]; then
            warn "先执行: sudo pacman -S$missing"
        else
            # shellcheck disable=SC2086
            sudo pacman -S --needed $missing \
                || die "pacman 安装失败。若是 filesystem conflict，见 troubleshooting.md 第 1 条。"
        fi
    else
        info "pacman 依赖齐全：nodejs npm pnpm git"
    fi
else
    warn "没找到 pacman，跳过发行版依赖检查。"
fi

# ---------- 3. Node 版本 ----------
command -v node >/dev/null 2>&1 || die "找不到 node，先装 nodejs。"
command -v npm  >/dev/null 2>&1 || die "找不到 npm，先装 npm（Arch 的 nodejs 不自动带 npm）。"

node_ver="$(node -v)"; node_ver="${node_ver#v}"
major="${node_ver%%.*}"
rest="${node_ver#*.}"; minor="${rest%%.*}"
info "Node.js $node_ver  /  npm $(npm -v)"

case "$node_ver" in
    *-*|*+*)
        die "Node 版本 '$node_ver' 是预发布版；dsh-TUI 要求 ^22.19 || >=24，请换正式版。" ;;
esac

if [ "$major" -eq 23 ]; then
    die "Node 23 不受支持（要求 ^22.19 || >=24），请换 22.19+ 或 24+。"
elif [ "$major" -eq 22 ]; then
    if [ "$minor" -lt 19 ]; then
        die "Node 22.$minor 太旧，需要 22.19 或更高。"
    fi
elif [ "$major" -lt 22 ]; then
    die "Node $node_ver 太旧，需要 ^22.19 || >=24。"
fi
info "Node 版本满足 dsh-TUI 的 ^22.19 || >=24"

# ---------- 4. pnpm（dsh-tui 首次启动要用它初始化 profile） ----------
if command -v pnpm >/dev/null 2>&1; then
    info "pnpm $(pnpm -v)"
else
    warn "没有 pnpm，而 dsh-tui 首次启动要靠它初始化 profile。"
    if [ "$CHECK_ONLY" -eq 0 ]; then
        info "安装 pnpm 到用户目录"
        npm install -g pnpm || die "pnpm 安装失败，试试 sudo pacman -S pnpm"
    fi
fi

# ---------- 5. npm 全局前缀 ----------
prefix="$(npm config get prefix)"
case "$prefix" in
    /usr|/usr/local)
        warn "npm 全局前缀是 $prefix（pacman 的地盘），改成用户目录更安全。"
        if [ "$CHECK_ONLY" -eq 0 ]; then
            npm config set prefix "$HOME/.local"
            prefix="$HOME/.local"
            info "已设置为 $prefix"
        fi
        ;;
esac
info "npm 全局前缀: $prefix"

bin_dir="$prefix/bin"
case ":$PATH:" in
    *":$bin_dir:"*) : ;;
    *)
        warn "$bin_dir 不在 PATH 里，请把它加进 shell 配置："
        printf '    export PATH="%s:$PATH"\n' "$bin_dir" >&2
        ;;
esac

# ---------- 6. 安装 ----------
if [ "$CHECK_ONLY" -eq 1 ]; then
    info "--check 模式：到此为止，没有安装任何东西。"
    exit 0
fi

info "安装 $DSH_PKG 与 $TUI_PKG"
npm install -g "$DSH_PKG" "$TUI_PKG" \
    || die "npm 安装失败，见 troubleshooting.md（网络代理 / EACCES / 版本冲突）。"

hash -r 2>/dev/null || true

# ---------- 7. 验证 ----------
missing_cmds=0
for cmd in dsh dsh-tui dst; do
    if command -v "$cmd" >/dev/null 2>&1; then
        info "OK   $cmd -> $(command -v "$cmd")"
    else
        warn "MISS $cmd 不在 PATH 里（多半是 $bin_dir 没加进 PATH）"
        missing_cmds=1
    fi
done

if command -v dsh-tui >/dev/null 2>&1; then
    info "dsh-tui 版本：$(dsh-tui version 2>&1 | head -n 1)"
    info "跑一次环境体检："
    dsh-tui doctor || warn "doctor 有告警，按提示处理（见 troubleshooting.md）。"
fi

if [ "$missing_cmds" -eq 1 ]; then
    die "有命令没进 PATH，先把 $bin_dir 加进 PATH，再重跑本脚本。"
fi

cat <<'EOF'

----------------------------------------------------------------
装好了。接下来三步：

  1) 配密钥（二选一）
       export DEEPSEEK_API_KEY="sk-..."   # deepseek-official 路由
       或启动后用 /provider              # 存进 DSH 凭据存储（推荐）

  2) 启动终端界面
       dsh-tui

  3) 恢复上次会话
       dsh-tui --resume

提醒：不要用 sudo 重跑本脚本；也不要把 .env / API Key 提交到 git。
----------------------------------------------------------------
EOF
