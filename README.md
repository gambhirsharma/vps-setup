# vps-setup

Minimal VPS bootstrap + Neovim/Vim config — extracted from [gambhir.dev](https://github.com/gambhirsharma/gambhir.dev) (`public/`).

Source of truth for `https://gambhir.dev/vps-setup.sh` and `https://gambhir.dev/nvim-setup.sh`.

## Contents

| File | Description | Source |
|------|-------------|--------|
| `vps-setup.sh` | Install `zsh`, `tmux`, `neovim` (official prebuilt binary) on fresh VPS | `gambhir.dev/public/vps-setup.sh` |
| `nvim-setup.sh` | Install minimal nvim/vim config (zero plugins) | `gambhir.dev/public/nvim-setup.sh` |
| `minimal-init.lua` | Minimal `init.lua` for nvim — ssh/VPS, no plugins | `gambhir.dev/public/minimal-init.lua` |
| `minimal-init.vimrc` | Minimal `.vimrc` for vim — ssh/VPS, no plugins | `gambhir.dev/public/minimal-init.vimrc` |

Hashes verified against `gambhir.dev` at import (2026-09-02).

## Quick start

### VPS bootstrap (zsh + tmux + nvim)

```bash
# from gambhir.dev (hosted)
curl -fsSL https://gambhir.dev/vps-setup.sh | bash
curl -fsSL https://gambhir.dev/vps-setup.sh | bash -s -- --help
curl -fsSL https://gambhir.dev/vps-setup.sh | bash -s -- --no-zsh
curl -fsSL https://gambhir.dev/vps-setup.sh | bash -s -- --set-shell

# from this repo (local clone)
./vps-setup.sh --help
./vps-setup.sh
./vps-setup.sh --no-zsh --no-tmux --set-shell

# env overrides
NVIM_VERSION=0.11.0 NVIM_INSTALL_DIR=/opt/nvim ./vps-setup.sh
```

What it does:
- `zsh`/`tmux` via system package manager (`apt`/`dnf`/`yum`/`pacman`/`apk`/`zypper`)
- `nvim` via official GitHub release binary (not package manager — distro repos lag):
  `https://github.com/neovim/neovim/releases/download/v$NVIM_VERSION/nvim-linux-<arch>.tar.gz`
  `x86_64` and `arm64` supported, extracted to `/opt/nvim-$VERSION`, symlinked to `/usr/local/bin/nvim`

### Minimal nvim/vim config

Zero-plugin, sane defaults for SSH/VPS.

```bash
# from gambhir.dev (hosted — single request, embedded configs)
curl -fsSL https://gambhir.dev/nvim-setup.sh | bash
curl -fsSL https://gambhir.dev/nvim | bash          # short alias (redirect)
curl -fsSL https://gambhir.dev/nvim.sh | bash

# from this repo
./nvim-setup.sh --help
./nvim-setup.sh                 # installs both
./nvim-setup.sh --vim-only      # only ~/.vimrc
./nvim-setup.sh --nvim-only     # only ~/.config/nvim/init.lua
./nvim-setup.sh --fetch         # fetch latest from https://gambhir.dev/minimal-init.*
./nvim-setup.sh --use-tmp       # prefer /tmp/minimal-init.* if present (dev)
```

What it does:
- `nvim` → `$XDG_CONFIG_HOME/nvim/init.lua` (`~/.config/nvim/init.lua`)
- `vim` → `~/.vimrc`
- Also copies to `/tmp/minimal-init.lua` / `/tmp/minimal-init.vimrc` for `nvim -u /tmp/minimal-init.lua` workflow
- Backs up existing files to `*.bak.<timestamp>`

Raw files without installer:

```bash
curl -fsSL https://gambhir.dev/minimal-init.lua -o ~/.config/nvim/init.lua
curl -fsSL https://gambhir.dev/minimal-init.vimrc -o ~/.vimrc
# try without installing
nvim -u ./minimal-init.lua
vim -u ./minimal-init.vimrc
# or
nvim -u /tmp/minimal-init.lua
```

## Neovim version

- Hard min `0.7` (`vim.keymap.set`, `nvim_create_autocmd`, `vim.highlight.on_yank`)
- Practical min `0.10` (`vim.diagnostic.config` uses `source="if_many"` / `border="rounded"` — strip to `virtual_text=true` on older)
- Tested on `v0.12.5`. Ubuntu `apt` ships `0.6` (jammy) / `0.9` (noble) — use `vps-setup.sh` or manual install:

```bash
curl -fsSLO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
# see vps-setup.sh:install_nvim for full flow
```

`minimal-init.vimrc` works with `vim >=8.2` (nvim extensions gated behind `has('nvim')`).

## Syncing from gambhir.dev

This repo is a split of `gambhir.dev/public/*`. To sync:

```bash
cp -v ../gambhir.dev/public/vps-setup.sh ./vps-setup.sh
cp -v ../gambhir.dev/public/nvim-setup.sh ./nvim-setup.sh
cp -v ../gambhir.dev/public/minimal-init.lua ./minimal-init.lua
cp -v ../gambhir.dev/public/minimal-init.vimrc ./minimal-init.vimrc
sha256sum vps-setup.sh nvim-setup.sh minimal-init.lua minimal-init.vimrc
```

Or hosted fetch:

```bash
curl -fsSL https://gambhir.dev/vps-setup.sh -o vps-setup.sh
curl -fsSL https://gambhir.dev/nvim-setup.sh -o nvim-setup.sh
curl -fsSL https://gambhir.dev/minimal-init.lua -o minimal-init.lua
curl -fsSL https://gambhir.dev/minimal-init.vimrc -o minimal-init.vimrc
chmod +x *.sh
```

## License

MIT — see `LICENSE`. Original template from [gambhir.dev](https://gambhir.dev) (MIT, Copyright (c) 2024 Kieran Wang).
