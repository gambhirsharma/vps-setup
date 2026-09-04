#!/usr/bin/env bash
# install.sh — orchestrator for vps-setup
# Runs vps-setup.sh (zsh/tmux/nvim binary) + nvim-setup.sh (minimal nvim/vim config)
# usage:
#   ./install.sh
#   ./install.sh --no-zsh --no-tmux --set-shell
#   ./install.sh --no-nvim --no-nvim-config
#   curl -fsSL https://raw.githubusercontent.com/gambhirsharma/vps-setup/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/gambhirsharma/vps-setup/main/install.sh | bash -s -- --help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { printf "${GREEN}[install]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[install]${NC} %s\n" "$*"; }
err()  { printf "${RED}[install]${NC} %s\n" "$*" >&2; }

# defaults — pass through to sub-scripts
VPS_ARGS=()
NVIM_ARGS=()
SKIP_VPS=0
SKIP_NVIM_CONFIG=0

usage() {
  cat <<'USAGE'
install.sh — full VPS setup orchestrator

Usage:
  ./install.sh [options]
  curl -fsSL https://raw.githubusercontent.com/gambhirsharma/vps-setup/main/install.sh | bash -s -- [options]

Options:
  --no-zsh              skip zsh (forwarded to vps-setup.sh)
  --no-zsh-config       skip zsh config (forwarded to vps-setup.sh)
  --no-tmux             skip tmux (forwarded to vps-setup.sh)
  --no-tmux-config      skip tmux config (forwarded to vps-setup.sh)
  --no-nvim             skip neovim binary (forwarded to vps-setup.sh)
  --set-shell           chsh default shell to zsh (forwarded to vps-setup.sh, default: on)
  --no-set-shell        don't change default shell (forwarded to vps-setup.sh)
  --no-nvim-config      skip nvim/vim config (don't run nvim-setup.sh)
  --nvim-only           only nvim config (forwarded to nvim-setup.sh)
  --vim-only            only vim config (forwarded to nvim-setup.sh)
  --no-vps              skip vps-setup.sh entirely (only nvim config)
  --help, -h            show this help

Env (forwarded):
  NVIM_VERSION, NVIM_INSTALL_DIR, NVIM_BIN_LINK  (vps-setup.sh)
  BASE_URL, XDG_CONFIG_HOME, TMUX_DEST, ZSHRC_DEST (vps-setup.sh / nvim-setup.sh)

Examples:
  ./install.sh
  ./install.sh --no-zsh --no-set-shell
  ./install.sh --no-vps --nvim-only
  ./install.sh --no-nvim-config
  ./install.sh --no-tmux-config
  ./install.sh --no-zsh-config
USAGE
  echo ""
  echo "Sub-script help:"
  echo "  --- vps-setup.sh ---"
  bash "$SCRIPT_DIR/vps-setup.sh" --help 2>&1 | sed 's/^/  /'
  echo "  --- nvim-setup.sh ---"
  bash "$SCRIPT_DIR/nvim-setup.sh" --help 2>&1 | sed 's/^/  /'
}

for arg in "$@"; do
  case "$arg" in
    --no-zsh)         VPS_ARGS+=("$arg") ;;
    --no-zsh-config)  VPS_ARGS+=("$arg") ;;
    --no-tmux)        VPS_ARGS+=("$arg") ;;
    --no-tmux-config) VPS_ARGS+=("$arg") ;;
    --no-nvim)        VPS_ARGS+=("$arg") ;;
    --set-shell)      VPS_ARGS+=("$arg") ;;
    --no-set-shell)   VPS_ARGS+=("$arg") ;;
    --no-nvim-config) SKIP_NVIM_CONFIG=1 ;;
    --no-vps)         SKIP_VPS=1 ;;
    --nvim-only|--vim-only|--no-nvim|--no-vim|--fetch|--use-tmp|--force|-f)
                      NVIM_ARGS+=("$arg") ;;
    --help|-h)        usage; exit 0 ;;
    *) err "unknown option: $arg (see --help)"; exit 1 ;;
  esac
done

if [[ "$SKIP_VPS" -eq 0 ]]; then
  info "step 1/2: vps-setup.sh ${VPS_ARGS[*]:-}"
  bash "$SCRIPT_DIR/vps-setup.sh" "${VPS_ARGS[@]}"
else
  warn "skipping vps-setup.sh (--no-vps)"
fi

if [[ "$SKIP_NVIM_CONFIG" -eq 0 ]]; then
  info "step 2/2: nvim-setup.sh ${NVIM_ARGS[*]:-}"
  bash "$SCRIPT_DIR/nvim-setup.sh" "${NVIM_ARGS[@]}"
else
  warn "skipping nvim config (--no-nvim-config)"
fi

echo ""
info "all done!"
echo "  vps:  zsh/tmux/nvim  -> ./vps-setup.sh --help"
echo "  nvim: minimal config -> ./nvim-setup.sh --help"
echo "  full: ./install.sh --help"
