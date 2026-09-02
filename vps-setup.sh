#!/usr/bin/env bash
# vps-setup.sh — install zsh, tmux, and neovim on a fresh VPS
# usage:
#   curl -fsSL https://gambhir.dev/vps-setup.sh | bash
#   curl -fsSL https://gambhir.dev/vps-setup.sh | bash -s -- --no-zsh
#   curl -fsSL https://gambhir.dev/vps-setup.sh | bash -s -- --set-shell
#   curl -fsSL https://gambhir.dev/vps-setup.sh | bash -s -- --help
#
# nvim is NOT installed via the system package manager — most distro repos
# ship an ancient version. instead this downloads the official prebuilt
# binary for the detected arch straight from the neovim GitHub release:
#   x86_64 -> https://github.com/neovim/neovim/releases/download/v$NVIM_VERSION/nvim-linux-x86_64.tar.gz
#   arm64  -> https://github.com/neovim/neovim/releases/download/v$NVIM_VERSION/nvim-linux-arm64.tar.gz
set -euo pipefail

NVIM_VERSION="${NVIM_VERSION:-0.11.0}"
NVIM_INSTALL_DIR="${NVIM_INSTALL_DIR:-/opt/nvim-${NVIM_VERSION}}"
NVIM_BIN_LINK="${NVIM_BIN_LINK:-/usr/local/bin/nvim}"
BASE_URL="${BASE_URL:-https://gambhir.dev}"
TMUX_DEST="${TMUX_DEST:-$HOME/.tmux.conf}"

DO_ZSH=1
DO_TMUX=1
DO_TMUX_CONFIG=1
DO_NVIM=1
SET_SHELL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

info()  { printf "${GREEN}[vps-setup]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[vps-setup]${NC} %s\n" "$*"; }
err()   { printf "${RED}[vps-setup]${NC} %s\n" "$*" >&2; }

usage() {
  cat <<'USAGE'
vps-setup.sh — install zsh, tmux, neovim (latest prebuilt binary) on a VPS

Usage:
  curl -fsSL https://gambhir.dev/vps-setup.sh | bash
  curl -fsSL https://gambhir.dev/vps-setup.sh | bash -s -- [options]

Options:
  --no-zsh          skip zsh
  --no-tmux         skip tmux binary
  --no-tmux-config  skip tmux config (~/.tmux.conf)
  --no-nvim         skip nvim
  --set-shell       chsh the current user's default shell to zsh after install
  --help, -h        show this help

Env:
  NVIM_VERSION      neovim version to install (default 0.11.0)
  NVIM_INSTALL_DIR  where the release tarball is extracted (default /opt/nvim-$NVIM_VERSION)
  NVIM_BIN_LINK     symlink path added to PATH (default /usr/local/bin/nvim)
  BASE_URL          base url for fetching configs (default https://gambhir.dev)
  TMUX_DEST         tmux config dest (default ~/.tmux.conf)

Notes:
  - zsh/tmux are installed via the system package manager (apt/dnf/yum/pacman/apk/zypper).
  - nvim is installed from the official GitHub release binary, not the package
    manager, since most distro repos lag far behind upstream.
  - tmux config is minimal (no plugins): prefix C-s, mouse, vi copy/paste, splits keep cwd.
  - arch is auto-detected: x86_64 and aarch64/arm64 are supported.
  - re-running is safe: an existing $NVIM_INSTALL_DIR is removed and replaced.
USAGE
}

need_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=""
  else
    if ! command -v sudo >/dev/null 2>&1; then
      err "not running as root and sudo is not available"
      exit 1
    fi
    SUDO="sudo"
  fi
}

detect_os() {
  OS="$(uname -s)"
  if [[ "$OS" != "Linux" ]]; then
    err "this script only supports Linux (detected: $OS)"
    exit 1
  fi

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID}"
  else
    DISTRO_ID="unknown"
    DISTRO_NAME="unknown"
  fi

  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"
  else
    PKG_MANAGER="none"
  fi

  info "detected OS: $DISTRO_NAME (package manager: $PKG_MANAGER)"
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64)
      NVIM_ARCH="x86_64" ;;
    aarch64|arm64)
      NVIM_ARCH="arm64" ;;
    *)
      err "unsupported architecture: $machine (nvim only ships x86_64/arm64 linux binaries)"
      exit 1 ;;
  esac
  info "detected arch: $machine -> nvim asset: nvim-linux-${NVIM_ARCH}.tar.gz"
}

pkg_install() {
  # pkg_install <pkg...>
  case "$PKG_MANAGER" in
    apt)
      $SUDO apt-get update -y
      $SUDO apt-get install -y "$@" ;;
    dnf)
      $SUDO dnf install -y "$@" ;;
    yum)
      $SUDO yum install -y "$@" ;;
    pacman)
      $SUDO pacman -Sy --noconfirm "$@" ;;
    apk)
      $SUDO apk add --no-cache "$@" ;;
    zypper)
      $SUDO zypper install -y "$@" ;;
    none)
      err "no supported package manager found (tried apt/dnf/yum/pacman/apk/zypper)"
      return 1 ;;
  esac
}

install_zsh() {
  if command -v zsh >/dev/null 2>&1; then
    info "zsh already installed ($(command -v zsh))"
  else
    info "installing zsh"
    pkg_install zsh
  fi

  if [[ "$SET_SHELL" -eq 1 ]]; then
    local zsh_path
    zsh_path="$(command -v zsh)"
    if [[ "${SHELL:-}" == "$zsh_path" ]]; then
      info "default shell is already zsh"
    else
      info "setting default shell to $zsh_path for $(whoami)"
      if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
        echo "$zsh_path" | $SUDO tee -a /etc/shells >/dev/null
      fi
      $SUDO chsh -s "$zsh_path" "$(whoami)" || warn "chsh failed — set the shell manually with: chsh -s $zsh_path"
    fi
  fi
}

install_tmux() {
  if command -v tmux >/dev/null 2>&1; then
    info "tmux already installed ($(command -v tmux)) — $(tmux -V)"
  else
    info "installing tmux"
    pkg_install tmux
  fi
}

backup_if_exists() {
  local dest="$1"
  if [[ -f "$dest" ]]; then
    local bak="${dest}.bak.$(date +%Y%m%d%H%M%S)"
    warn "backing up $dest -> $bak"
    cp -a "$dest" "$bak"
  fi
}

write_embedded_tmux() {
  local dest="$1"
  cat > "$dest" <<'TMUXCONF'
# minimal-tmux.conf — ssh/VPS, zero plugins, only changed defaults
# source: https://github.com/gambhirsharma/vps-setup
# install: cp minimal-tmux.conf ~/.tmux.conf && tmux source ~/.tmux.conf
#     or:  tmux -f /tmp/minimal-tmux.conf
# reload inside tmux: <prefix> + r  (prefix is C-s)

# ── prefix (changed from default C-b) ──────────────────────────────────
unbind C-b
set -g prefix C-s
bind C-s send-prefix

# ── general ────────────────────────────────────────────────────────────
set -g mouse on
set -g set-clipboard on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g history-limit 50000
set -g display-time 2000
set -sg escape-time 10

# true color + passthrough (for nvim / images)
set -ga terminal-overrides ",xterm-256color:Tc"
set -g allow-passthrough on
# set -g default-terminal "tmux-256color"

# status bar on top (like your local)
set -g status on
set -g status-position top

# ── reload ─────────────────────────────────────────────────────────────
bind r source-file ~/.tmux.conf \; display "Reloaded ~/.tmux.conf"

# ── vi mode ────────────────────────────────────────────────────────────
setw -g mode-keys vi

# ── pane navigation (prefix + h/j/k/l) ─────────────────────────────────
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# ── splits keep cwd (prefix + | / -) ──────────────────────────────────
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
# override defaults to also keep cwd
bind '"' split-window -v -c "#{pane_current_path}"
bind %  split-window -h -c "#{pane_current_path}"

# ── copy / paste (vi) ──────────────────────────────────────────────────
# enter copy mode: <prefix> + [
# start selection: v (or V for line), C-v for block, y to yank
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi C-v send -X rectangle-toggle
bind -T copy-mode-vi y send -X copy-selection-and-cancel
# mouse drag copies to tmux buffer and exits copy mode
bind -T copy-mode-vi MouseDragEnd1Pane send -X copy-selection-and-cancel
# paste: <prefix> + p  (also <prefix> + ] is default)
bind p paste-buffer
# optional: yank to system clipboard if tool exists (xclip/xsel/wl-copy/pbcopy)
# will silently fallback to tmux buffer if no tool
# uncomment if your VPS has xclip/wl-clipboard installed:
# bind -T copy-mode-vi y send -X copy-pipe-and-cancel "sh -c 'command -v wl-copy >/dev/null && wl-copy || command -v xclip >/dev/null && xclip -i -selection clipboard || command -v xsel >/dev/null && xsel -i -b || cat >/dev/null'"

# ── toggle status bar (prefix + a) ─────────────────────────────────────
bind a run-shell "tmux show -gqv status | grep -q '^on$' && tmux set -g status off || tmux set -g status on"

# ── borders ────────────────────────────────────────────────────────────
set -g pane-active-border-style 'fg=magenta,bold'
set -g pane-border-style 'fg=brightblack'
# tmux >= 3.3: thicker borders + indicators (uncomment if supported)
# set -g pane-border-lines heavy
# set -g pane-border-indicators both

# ── status bar (minimal, no plugins) ───────────────────────────────────
set -g status-style 'bg=default,fg=white'
set -g status-left '#[fg=green,bold][#S] '
set -g status-left-length 20
set -g status-right '#{?client_prefix,#[fg=black]#[bg=yellow] PREFIX #[default] ,}#[fg=cyan]#h #[fg=brightblack]│ #[fg=white]%Y-%m-%d %H:%M'
set -g status-right-length 60
set -g window-status-current-style 'fg=magenta,bold'
set -g window-status-style 'fg=brightblack'
TMUXCONF
}

install_tmux_config() {
  local src=""
  # prefer local file if cloned (~/vps-setup/minimal-tmux.conf)
  if [[ -f "$SCRIPT_DIR/minimal-tmux.conf" ]]; then
    src="$SCRIPT_DIR/minimal-tmux.conf"
  elif [[ -f ./minimal-tmux.conf ]]; then
    src="./minimal-tmux.conf"
  fi

  info "installing tmux config -> $TMUX_DEST"
  mkdir -p "$(dirname "$TMUX_DEST")"
  backup_if_exists "$TMUX_DEST"

  if [[ -n "$src" ]]; then
    info "using $src"
    cp -a "$src" "$TMUX_DEST"
  else
    # fallback: embedded (for curl|bash without clone) or fetch
    if command -v curl >/dev/null 2>&1; then
      info "fetching $BASE_URL/minimal-tmux.conf"
      if curl -fsSL "$BASE_URL/minimal-tmux.conf" -o "$TMUX_DEST" 2>/dev/null; then
        info "fetched tmux config from $BASE_URL"
      else
        warn "fetch failed, using embedded tmux config"
        write_embedded_tmux "$TMUX_DEST"
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -qO "$TMUX_DEST" "$BASE_URL/minimal-tmux.conf" 2>/dev/null; then
        info "fetched tmux config from $BASE_URL"
      else
        warn "fetch failed, using embedded tmux config"
        write_embedded_tmux "$TMUX_DEST"
      fi
    else
      write_embedded_tmux "$TMUX_DEST"
    fi
  fi

  mkdir -p /tmp 2>/dev/null || true
  cp -a "$TMUX_DEST" /tmp/minimal-tmux.conf 2>/dev/null || true
  info "tmux config installed at $TMUX_DEST (also copied to /tmp/minimal-tmux.conf)"

  # validate
  if command -v tmux >/dev/null 2>&1; then
    if tmux -f "$TMUX_DEST" start-server 2>&1 | grep -q "error\|unknown"; then
      warn "tmux config has warnings, check with: tmux source-file $TMUX_DEST"
    fi
    # kill the test server if we started one
    tmux -L test-tmux-config kill-server 2>/dev/null || true
  fi
}

install_nvim() {
  local url tarball extract_dir
  url="https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz"
  tarball="$(mktemp -t nvim-XXXXXX.tar.gz)"

  info "downloading nvim v${NVIM_VERSION} ($NVIM_ARCH) from $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tarball"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tarball" "$url"
  else
    err "need curl or wget to download nvim"
    exit 1
  fi

  info "extracting to $NVIM_INSTALL_DIR"
  $SUDO rm -rf "$NVIM_INSTALL_DIR"
  $SUDO mkdir -p "$NVIM_INSTALL_DIR"
  $SUDO tar -xzf "$tarball" -C "$NVIM_INSTALL_DIR" --strip-components=1
  rm -f "$tarball"

  info "linking $NVIM_BIN_LINK -> $NVIM_INSTALL_DIR/bin/nvim"
  $SUDO ln -sf "$NVIM_INSTALL_DIR/bin/nvim" "$NVIM_BIN_LINK"

  if command -v nvim >/dev/null 2>&1; then
    info "installed: $(nvim --version | head -n1)"
  else
    warn "nvim installed to $NVIM_BIN_LINK but it's not on PATH yet — open a new shell"
  fi
}

# parse args
for arg in "$@"; do
  case "$arg" in
    --no-zsh)         DO_ZSH=0 ;;
    --no-tmux)        DO_TMUX=0 ;;
    --no-tmux-config) DO_TMUX_CONFIG=0 ;;
    --no-nvim)        DO_NVIM=0 ;;
    --set-shell)      SET_SHELL=1 ;;
    --help|-h)        usage; exit 0 ;;
    *) err "unknown option: $arg (see --help)"; exit 1 ;;
  esac
done

need_sudo
detect_os
[[ "$DO_NVIM" -eq 1 ]] && detect_arch

if [[ "$DO_ZSH" -eq 1 ]]; then install_zsh; fi
if [[ "$DO_TMUX" -eq 1 ]]; then install_tmux; fi
# install tmux config if tmux was requested (or already present) and config not skipped
if [[ "$DO_TMUX_CONFIG" -eq 1 ]]; then
  if [[ "$DO_TMUX" -eq 1 ]] || command -v tmux >/dev/null 2>&1; then
    install_tmux_config
  else
    warn "skipping tmux config (tmux not installed and --no-tmux)"
  fi
fi
if [[ "$DO_NVIM" -eq 1 ]]; then install_nvim; fi

echo ""
info "done. installed:"
[[ "$DO_ZSH" -eq 1 ]]  && echo "  zsh:  $(command -v zsh 2>/dev/null || echo 'not found')"
[[ "$DO_TMUX" -eq 1 ]] && echo "  tmux: $(command -v tmux 2>/dev/null || echo 'not found')"
if [[ "$DO_TMUX_CONFIG" -eq 1 ]]; then
  echo "  tmux conf: $TMUX_DEST"
fi
[[ "$DO_NVIM" -eq 1 ]] && echo "  nvim: $(command -v nvim 2>/dev/null || echo 'not found')"
echo ""
echo "  curl -fsSL https://gambhir.dev/nvim-setup.sh | bash   # minimal nvim/vim config"
echo "  tmux source ~/.tmux.conf  # reload tmux (prefix C-s + r)"
echo ""
info "everything is in place — you can start hacking!!"
