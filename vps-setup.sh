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
ZSHRC_DEST="${ZSHRC_DEST:-$HOME/.zshrc}"
ZSH_PLUGINS_DIR="${ZSH_PLUGINS_DIR:-$HOME/.zsh}"

DO_ZSH=1
DO_ZSH_CONFIG=1
DO_TMUX=1
DO_TMUX_CONFIG=1
DO_NVIM=1
SET_SHELL=1

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
  --no-zsh-config   skip zsh config (~/.zshrc)
  --no-tmux         skip tmux binary
  --no-tmux-config  skip tmux config (~/.tmux.conf)
  --no-nvim         skip nvim
  --set-shell       chsh the current user's default shell to zsh after install (default: on)
  --no-set-shell    don't change default shell
  --help, -h        show this help

Env:
  NVIM_VERSION      neovim version to install (default 0.11.0)
  NVIM_INSTALL_DIR  where the release tarball is extracted (default /opt/nvim-$NVIM_VERSION)
  NVIM_BIN_LINK     symlink path added to PATH (default /usr/local/bin/nvim)
  BASE_URL          base url for fetching configs (default https://gambhir.dev)
  TMUX_DEST         tmux config dest (default ~/.tmux.conf)
  ZSHRC_DEST        zsh config dest (default ~/.zshrc)
  ZSH_PLUGINS_DIR   zsh plugins dir (default ~/.zsh)

Notes:
  - zsh/tmux are installed via the system package manager (apt/dnf/yum/pacman/apk/zypper).
  - zsh config is minimal: fish-like autosuggestions from history, 2-line prompt
    (line 1: user@host cwd git branch, line 2: ❯), completion, aliases (ks=nvim).
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
}

set_default_shell() {
  if ! command -v zsh >/dev/null 2>&1; then
    warn "zsh not found, skipping chsh"
    return 0
  fi
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
}

backup_if_exists() {
  local dest="$1"
  if [[ -f "$dest" ]]; then
    local bak="${dest}.bak.$(date +%Y%m%d%H%M%S)"
    warn "backing up $dest -> $bak"
    cp -a "$dest" "$bak"
  fi
}

install_zsh_plugins() {
  # ensure git for cloning plugins
  if ! command -v git >/dev/null 2>&1; then
    info "git not found, installing git for zsh plugins"
    pkg_install git || warn "failed to install git — plugins will be skipped"
  fi
  if ! command -v git >/dev/null 2>&1; then
    warn "git still not available — skipping zsh plugin install"
    return 0
  fi
  mkdir -p "$ZSH_PLUGINS_DIR"
  local dest
  # zsh-autosuggestions (fish-like history suggestions)
  dest="$ZSH_PLUGINS_DIR/zsh-autosuggestions"
  if [[ -d "$dest/.git" ]]; then
    info "updating zsh-autosuggestions at $dest"
    git -C "$dest" pull --ff-only --quiet 2>/dev/null || warn "failed to update $dest"
  elif [[ -d "$dest" ]]; then
    warn "$dest exists but not a git repo, skipping"
  else
    info "cloning zsh-autosuggestions -> $dest"
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$dest" 2>/dev/null || warn "failed to clone zsh-autosuggestions"
  fi
  # zsh-syntax-highlighting (keep last, must be sourced last)
  dest="$ZSH_PLUGINS_DIR/zsh-syntax-highlighting"
  if [[ -d "$dest/.git" ]]; then
    info "updating zsh-syntax-highlighting at $dest"
    git -C "$dest" pull --ff-only --quiet 2>/dev/null || warn "failed to update $dest"
  elif [[ -d "$dest" ]]; then
    warn "$dest exists but not a git repo, skipping"
  else
    info "cloning zsh-syntax-highlighting -> $dest"
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$dest" 2>/dev/null || warn "failed to clone zsh-syntax-highlighting"
  fi
}

write_embedded_zshrc() {
  local dest="$1"
  cat > "$dest" <<'ZSHRC'
# minimal-zshrc — ssh/VPS, zero framework, only sane defaults
# source: https://github.com/gambhirsharma/vps-setup
# install: cp minimal-zshrc ~/.zshrc && exec zsh
#     or:  zsh  # (uses ~/.zshrc)
# notes: plugins are auto-cloned to ~/.zsh/ by vps-setup.sh

# ── early exit for non-interactive ───────────────────────────────────
[[ $- != *i* ]] && return

# ── TERM fallback ──────────────────────────────────────────────────────
# modern local terminals (Ghostty, kitty, WezTerm, ...) send a TERM value
# whose terminfo entry often isn't installed on a fresh/minimal remote host,
# breaking ncurses tools (tmux, clear, less, ...) with errors like
# "unknown terminal type" or "missing or unsuitable terminal". fall back to
# a widely-available entry instead.
if [[ -n "$TERM" ]] && ! infocmp "$TERM" >/dev/null 2>&1; then
  export TERM=xterm-256color
fi

# ── XDG / cache ──────────────────────────────────────────────────────
[[ -z "${XDG_CACHE_HOME:-}" ]] && XDG_CACHE_HOME="$HOME/.cache"
[[ -z "${XDG_DATA_HOME:-}" ]] && XDG_DATA_HOME="$HOME/.local/share"
mkdir -p "$XDG_CACHE_HOME/zsh" 2>/dev/null

# ── history ──────────────────────────────────────────────────────────
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
setopt EXTENDED_HISTORY
# don't record dup consecutively: HIST_IGNORE_DUPS already, but also:
setopt HIST_FIND_NO_DUPS

# ── general options ──────────────────────────────────────────────────
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP
setopt NO_CASE_GLOB
setopt EXTENDED_GLOB
setopt GLOB_DOTS
unsetopt FLOW_CONTROL

# ── completion ───────────────────────────────────────────────────────
autoload -Uz compinit
# only regenerate compdump once a day
if [[ -n "$XDG_CACHE_HOME/zsh/zcompdump(#qN.mh+24)" ]]; then
  compinit -d "$XDG_CACHE_HOME/zsh/zcompdump"
else
  compinit -C -d "$XDG_CACHE_HOME/zsh/zcompdump"
fi
# case-insensitive, partial word, substring
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' rehash true
zstyle ':completion:*' completer _complete _match _approximate
zstyle ':completion:*:approximate:*' max-errors 1 numeric
zstyle ':completion:*' squeeze-slashes true
# kill completion
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
# cache
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"

# ── keybindings (emacs) ──────────────────────────────────────────────
bindkey -e
# history search with prefix (type prefix then up/down)
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search   # Up
bindkey '^[[B' down-line-or-beginning-search # Down
bindkey '^p' up-line-or-beginning-search
bindkey '^n' down-line-or-beginning-search
# home/end, delete
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word   # Ctrl+Right
bindkey '^[[1;5D' backward-word  # Ctrl+Left
# edit command line
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^xe' edit-command-line
bindkey '^x^e' edit-command-line

# ── plugins: autosuggestions + syntax-highlighting ───────────────────
# installed by vps-setup.sh to ~/.zsh/ (or $ZSH_PLUGINS_DIR)
# autosuggestions: fish-like ghost text from history (→ to accept)
: "${ZSH_PLUGINS_DIR:=$HOME/.zsh}"
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_USE_ASYNC=1
# accept suggestion: Right → or Ctrl-F or End
# (Right arrow is bound by the plugin to forward-char/accept if at eol)
if [[ -f "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
  bindkey '^f' autosuggest-accept       # Ctrl-F accept
  bindkey '^e' autosuggest-accept       # Ctrl-E accept (end)
  bindkey '^[[C' forward-char           # Right arrow (also works)
elif [[ -f "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
  bindkey '^f' autosuggest-accept
  bindkey '^e' autosuggest-accept
  bindkey '^[[C' forward-char
fi
# syntax highlighting (must be last)
if [[ -f "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
elif [[ -f "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
# optional: completions collection
if [[ -f "$ZSH_PLUGINS_DIR/zsh-completions/zsh-completions.plugin.zsh" ]]; then
  fpath=("$ZSH_PLUGINS_DIR/zsh-completions/src" $fpath)
elif [[ -f "$HOME/.zsh/zsh-completions/zsh-completions.plugin.zsh" ]]; then
  fpath=("$HOME/.zsh/zsh-completions/src" $fpath)
fi

# ── colors / ls ──────────────────────────────────────────────────────
autoload -Uz colors && colors
export CLICOLOR=1
if ls --color=auto >/dev/null 2>&1; then
  alias ls='ls --color=auto -F'
  alias ll='ls --color=auto -lAhF'
else
  alias ls='ls -G -F'
  alias ll='ls -G -lAhF'
fi
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
# safety
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
# nvim shortcuts
alias ks='nvim'
alias vim='nvim'
alias vi='nvim'
alias v='nvim'

# ── prompt: two-line, shows cwd + git + status ───────────────────────
# line 1: ┌─ [user@host] [cwd] [git:branch] [venv] [time]
# line 2: └─ ❯  (green on success, red on failure)
autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git*' check-for-changes true
zstyle ':vcs_info:git*' stagedstr '%F{green}●%f'
zstyle ':vcs_info:git*' unstagedstr '%F{yellow}●%f'
zstyle ':vcs_info:git*' formats ' %F{magenta} %b%f%c%u'
zstyle ':vcs_info:git*' actionformats ' %F{magenta} %b|%a%f%c%u'
# faster git check: don't check untracked if slow (optional)
# zstyle ':vcs_info:git*' check-for-changes false

precmd() {
  vcs_info
  # window title
  print -Pn "\e]0;%n@%m: %~\a"
}

# show python venv / conda
_venv_info() {
  if [[ -n "$VIRTUAL_ENV" ]]; then
    echo " %F{cyan}(${VIRTUAL_ENV:t})%f"
  elif [[ -n "$CONDA_DEFAULT_ENV" && "$CONDA_DEFAULT_ENV" != "base" ]]; then
    echo " %F{cyan}($CONDA_DEFAULT_ENV)%f"
  fi
}

# allow prompt substitution
setopt PROMPT_SUBST

# first line: box + user@host + dir + git + venv + exit code (if failed)
# second line: prompt char
PROMPT='
%F{cyan}┌─%f %F{green}%n@%m%f %F{blue}%~%f${vcs_info_msg_0_}$(_venv_info) %(?.%F{8}.%F{red}✘ %?%f)
%F{cyan}└─%f %(?.%F{magenta}.%F{red})❯%f '

# right prompt: time (dim)
RPROMPT='%F{8}%*%f'

# shorter prompt for root
if [[ $UID -eq 0 ]]; then
  PROMPT='
%F{cyan}┌─%f %F{red}%n@%m%f %F{blue}%~%f${vcs_info_msg_0_}$(_venv_info) %(?.%F{8}.%F{red}✘ %?%f)
%F{cyan}└─%f %F{red}#%f '
fi

# ── terminal title + emacs tramp fix ─────────────────────────────────
# (avoid breaking tramp)
[[ $TERM == "dumb" ]] && unsetopt zle && PS1='$ ' && return

# ── better history search with fzf if available (optional) ────────────
if command -v fzf >/dev/null 2>&1; then
  # Ctrl-R: fzf history
  fzf-history-widget() {
    local selected
    selected=$(fc -rl 1 | awk '{ cmd=$0; sub(/^[ ]*[0-9]*[ ]*/, "", cmd); if (!seen[cmd]++) print $0 }' | fzf --query="$LBUFFER" --height=40% --reverse --tac | sed 's/^[ ]*[0-9]*[ ]*//')
    if [[ -n "$selected" ]]; then
      LBUFFER="$selected"
      CURSOR=$#LBUFFER
    fi
    zle redisplay
  }
  zle -N fzf-history-widget
  bindkey '^R' fzf-history-widget
fi

# ── load local overrides ─────────────────────────────────────────────
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# ── helpful env ──────────────────────────────────────────────────────
export EDITOR="${EDITOR:-nvim}"
export VISUAL="$EDITOR"
# reduce delay for vi mode if switched later
export KEYTIMEOUT=1
# pagers
export LESS='-R'
# ensure ~/.local/bin on path
[[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

# ── done ─────────────────────────────────────────────────────────────
# tip: ghost suggestion from history appears in gray → press → or Ctrl-F to accept
#      prompt is two lines: top shows user@host, cwd, git branch, time; bottom is input
ZSHRC
}

install_zsh_config() {
  local src=""
  if [[ -f "$SCRIPT_DIR/minimal-zshrc" ]]; then
    src="$SCRIPT_DIR/minimal-zshrc"
  elif [[ -f ./minimal-zshrc ]]; then
    src="./minimal-zshrc"
  fi
  info "installing zsh config -> $ZSHRC_DEST"
  mkdir -p "$(dirname "$ZSHRC_DEST")"
  backup_if_exists "$ZSHRC_DEST"
  if [[ -n "$src" ]]; then
    info "using $src"
    cp -a "$src" "$ZSHRC_DEST"
  else
    if command -v curl >/dev/null 2>&1; then
      info "fetching $BASE_URL/minimal-zshrc"
      if curl -fsSL "$BASE_URL/minimal-zshrc" -o "$ZSHRC_DEST" 2>/dev/null; then
        info "fetched zsh config from $BASE_URL"
      else
        warn "fetch failed, using embedded zsh config"
        write_embedded_zshrc "$ZSHRC_DEST"
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -qO "$ZSHRC_DEST" "$BASE_URL/minimal-zshrc" 2>/dev/null; then
        info "fetched zsh config from $BASE_URL"
      else
        warn "fetch failed, using embedded zsh config"
        write_embedded_zshrc "$ZSHRC_DEST"
      fi
    else
      write_embedded_zshrc "$ZSHRC_DEST"
    fi
  fi
  mkdir -p /tmp 2>/dev/null || true
  cp -a "$ZSHRC_DEST" /tmp/minimal-zshrc 2>/dev/null || true
  info "zsh config installed at $ZSHRC_DEST (also copied to /tmp/minimal-zshrc)"
  install_zsh_plugins
  if command -v zsh >/dev/null 2>&1; then
    if ! zsh -n "$ZSHRC_DEST" 2>&1; then
      warn "zsh config has syntax warnings, check with: zsh -n $ZSHRC_DEST"
    else
      info "zsh config syntax OK"
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
    --no-zsh-config)  DO_ZSH_CONFIG=0 ;;
    --no-tmux)        DO_TMUX=0 ;;
    --no-tmux-config) DO_TMUX_CONFIG=0 ;;
    --no-nvim)        DO_NVIM=0 ;;
    --set-shell)      SET_SHELL=1 ;;
    --no-set-shell)   SET_SHELL=0 ;;
    --help|-h)        usage; exit 0 ;;
    *) err "unknown option: $arg (see --help)"; exit 1 ;;
  esac
done

need_sudo
detect_os
[[ "$DO_NVIM" -eq 1 ]] && detect_arch

if [[ "$DO_ZSH" -eq 1 ]]; then install_zsh; fi
if [[ "$DO_ZSH_CONFIG" -eq 1 ]]; then
  if [[ "$DO_ZSH" -eq 1 ]] || command -v zsh >/dev/null 2>&1; then
    install_zsh_config
  else
    warn "skipping zsh config (zsh not installed and --no-zsh)"
  fi
fi
if [[ "$SET_SHELL" -eq 1 ]]; then
  if [[ "$DO_ZSH" -eq 1 ]] || command -v zsh >/dev/null 2>&1; then
    set_default_shell
  else
    warn "skipping chsh (zsh not installed)"
  fi
fi
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
if [[ "$DO_ZSH_CONFIG" -eq 1 ]]; then
  echo "  zsh conf: $ZSHRC_DEST"
fi
if [[ "$SET_SHELL" -eq 1 ]]; then
  echo "  shell:  $SHELL (default -> $(command -v zsh 2>/dev/null || echo 'zsh not found'))"
fi
[[ "$DO_TMUX" -eq 1 ]] && echo "  tmux: $(command -v tmux 2>/dev/null || echo 'not found')"
if [[ "$DO_TMUX_CONFIG" -eq 1 ]]; then
  echo "  tmux conf: $TMUX_DEST"
fi
[[ "$DO_NVIM" -eq 1 ]] && echo "  nvim: $(command -v nvim 2>/dev/null || echo 'not found')"
echo ""
echo "  exec zsh                        # start zsh (new shell)"
echo "  curl -fsSL https://gambhir.dev/nvim-setup.sh | bash   # minimal nvim/vim config"
echo "  tmux source ~/.tmux.conf  # reload tmux (prefix C-s + r)"
echo ""
info "everything is in place — you can start hacking!!"
