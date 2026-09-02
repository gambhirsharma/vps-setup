# vps-setup

Single source of truth for VPS bootstrap — `gambhir.dev` now only hosts a thin entrypoint (`https://gambhir.dev/install.sh`) that installs `git`, clones this repo, and runs `install.sh`.

Migrated from `gambhir.dev/public/*` (2026-09-02).

## Contents

| File | Description |
|------|-------------|
| `install.sh` | **Orchestrator** — runs `vps-setup.sh` + `nvim-setup.sh` (what the bootstrap executes) |
| `vps-setup.sh` | Install `zsh`, `tmux`, `neovim` (official prebuilt binary) |
| `nvim-setup.sh` | Install minimal nvim/vim config (zero plugins, embedded) |
| `minimal-init.lua` | Minimal `init.lua` for nvim — ssh/VPS |
| `minimal-init.vimrc` | Minimal `.vimrc` for vim — ssh/VPS |

## Quick start — fresh VPS

### 1. Via gambhir.dev bootstrap (recommended)

```bash
curl -fsSL https://gambhir.dev/install.sh | bash
curl -fsSL https://gambhir.dev/install.sh | bash -s -- --help
curl -fsSL https://gambhir.dev/install.sh | bash -s -- --no-zsh --set-shell
curl -fsSL https://gambhir.dev/install.sh | bash -s -- --no-nvim-config
curl -fsSL https://gambhir.dev/install.sh | bash -s -- --no-vps --nvim-only

# aliases — same bootstrap
curl -fsSL https://gambhir.dev/vps-setup.sh | bash
curl -fsSL https://gambhir.dev/bootstrap.sh | bash
```

Bootstrap flow:
1. installs `git` if missing (`apt`/`dnf`/`yum`/`pacman`/`apk`/`zypper` + `sudo`)
2. clones `https://github.com/gambhirsharma/vps-setup.git` to `~/vps-setup` (`$VPS_SETUP_DIR`)
3. runs `~/vps-setup/install.sh` with forwarded args

```bash
# env overrides
VPS_SETUP_DIR=/tmp/vps-setup curl -fsSL https://gambhir.dev/install.sh | bash
NVIM_VERSION=0.11.0 curl -fsSL https://gambhir.dev/install.sh | bash
```

### 2. Direct from this repo (after clone)

```bash
git clone https://github.com/gambhirsharma/vps-setup.git ~/vps-setup
cd ~/vps-setup

./install.sh --help
./install.sh                              # full: vps + nvim config
./install.sh --no-zsh --set-shell         # forwarded to vps-setup.sh
./install.sh --no-vps --nvim-only         # only nvim config
./install.sh --no-nvim-config             # skip nvim config

# granular
./vps-setup.sh --help
./vps-setup.sh --no-zsh --no-tmux
NVIM_VERSION=0.11.0 ./vps-setup.sh

./nvim-setup.sh --help
./nvim-setup.sh --vim-only
./nvim-setup.sh --nvim-only --fetch
```

### 3. Raw files (no installer)

```bash
# from this repo
nvim -u ./minimal-init.lua
vim -u ./minimal-init.vimrc

# from raw github
curl -fsSL https://raw.githubusercontent.com/gambhirsharma/vps-setup/main/minimal-init.lua -o ~/.config/nvim/init.lua
curl -fsSL https://raw.githubusercontent.com/gambhirsharma/vps-setup/main/minimal-init.vimrc -o ~/.vimrc
```

## What each script does

**`vps-setup.sh`** — `zsh`/`tmux` via package manager, `nvim` via official GitHub release binary:
- `https://github.com/neovim/neovim/releases/download/v$NVIM_VERSION/nvim-linux-<arch>.tar.gz`
- `x86_64` and `arm64` supported, extracted to `/opt/nvim-$VERSION`, symlinked to `/usr/local/bin/nvim`

**`nvim-setup.sh`** — zero-plugin sane defaults for SSH:
- `nvim` → `$XDG_CONFIG_HOME/nvim/init.lua` (`~/.config/nvim/init.lua`)
- `vim` → `~/.vimrc`
- also copies to `/tmp/minimal-init.lua` / `/tmp/minimal-init.vimrc` for `nvim -u /tmp/minimal-init.lua`
- backs up existing files to `*.bak.<timestamp>`

**`install.sh`** — orchestrator, 2 steps with forwarded flags.

## Neovim version

- Hard min `0.7` (`vim.keymap.set`, `nvim_create_autocmd`, `vim.highlight.on_yank`)
- Practical min `0.10` (`vim.diagnostic.config` uses `source="if_many"` / `border="rounded"` — strip to `virtual_text=true` on older)
- Tested on `v0.12.5`. Ubuntu `apt` ships `0.6` (jammy) / `0.9` (noble) — use `vps-setup.sh`.

`minimal-init.vimrc` works with `vim >=8.2` (nvim extensions gated behind `has('nvim')`).

## License

MIT — see `LICENSE`. Original template from [gambhir.dev](https://gambhir.dev) (MIT, Copyright (c) 2024 Kieran Wang).
