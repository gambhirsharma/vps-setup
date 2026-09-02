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

DO_ZSH=1
DO_TMUX=1
DO_NVIM=1
SET_SHELL=0

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
  --no-zsh        skip zsh
  --no-tmux       skip tmux
  --no-nvim       skip nvim
  --set-shell     chsh the current user's default shell to zsh after install
  --help, -h      show this help

Env:
  NVIM_VERSION      neovim version to install (default 0.11.0)
  NVIM_INSTALL_DIR  where the release tarball is extracted (default /opt/nvim-$NVIM_VERSION)
  NVIM_BIN_LINK     symlink path added to PATH (default /usr/local/bin/nvim)

Notes:
  - zsh/tmux are installed via the system package manager (apt/dnf/yum/pacman/apk/zypper).
  - nvim is installed from the official GitHub release binary, not the package
    manager, since most distro repos lag far behind upstream.
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
    --no-zsh)     DO_ZSH=0 ;;
    --no-tmux)    DO_TMUX=0 ;;
    --no-nvim)    DO_NVIM=0 ;;
    --set-shell)  SET_SHELL=1 ;;
    --help|-h)    usage; exit 0 ;;
    *) err "unknown option: $arg (see --help)"; exit 1 ;;
  esac
done

need_sudo
detect_os
[[ "$DO_NVIM" -eq 1 ]] && detect_arch

if [[ "$DO_ZSH" -eq 1 ]]; then install_zsh; fi
if [[ "$DO_TMUX" -eq 1 ]]; then install_tmux; fi
if [[ "$DO_NVIM" -eq 1 ]]; then install_nvim; fi

echo ""
info "done. installed:"
[[ "$DO_ZSH" -eq 1 ]]  && echo "  zsh:  $(command -v zsh 2>/dev/null || echo 'not found')"
[[ "$DO_TMUX" -eq 1 ]] && echo "  tmux: $(command -v tmux 2>/dev/null || echo 'not found')"
[[ "$DO_NVIM" -eq 1 ]] && echo "  nvim: $(command -v nvim 2>/dev/null || echo 'not found')"
echo ""
echo "  curl -fsSL https://gambhir.dev/nvim-setup.sh | bash   # minimal nvim/vim config"
echo ""
info "everything is in place — you can start hacking!!"
