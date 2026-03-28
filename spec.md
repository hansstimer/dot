# dot — Cross-Platform Dotfiles & Bootstrap

## Goal

A single repo that configures a consistent development environment on macOS and Linux (including ephemeral remote hosts). One command to push, install, and activate. Works on machines with zsh or bash, old or current tooling.

---

## Principles

1. **Idempotent** — Running setup twice is safe and fast.
2. **Minimal dependencies** — Bootstrap requires only a POSIX shell (`zsh` on macOS, `bash` 4.2+ on Linux), `curl`, and `git`. The install script is written in bash but invoked via `#!/usr/bin/env bash` on Linux and can be run under zsh on macOS where bash is ancient (3.2).
3. **Shell-agnostic configs** — Shared aliases/env live in POSIX-compatible files sourced by both `.bashrc` and `.zshrc`.
4. **Detect, don't assume** — OS, shell, package manager, SSH vs local, tmux presence, sudo availability — all detected at runtime.
5. **tmux from nightly** — tmux must be built from the nightly/overnight build. Upstream has fixes critical for Claude Code that are not yet in released versions. `packages.sh` handles building from source when the system tmux is too old or missing these patches.
6. **Fail gracefully** — All scripts use `set -euo pipefail`. Each setup phase reports success/failure independently. A failed package install does not block config linking.
7. **Tiered deployment** — `--minimal` for configs-only, full install by default on local, `--remote` for remote hosts.

---

## Compatibility

| Platform | Min Version | Notes |
|---|---|---|
| macOS | 12+ | Homebrew, zsh default |
| Ubuntu | 18.04+ | apt |
| Debian | 10+ | apt |
| RHEL/CentOS | 7+ | yum (7), dnf (8+) |
| Amazon Linux | 2+ | yum (AL2), dnf (AL2023) |
| Fedora | 36+ | dnf |
| Alpine | 3.14+ | apk |
| Arch | rolling | pacman |

**Shell compatibility:** Scripts must work under both `bash` 4.2+ (RHEL 7 / Amazon Linux 2) and `zsh` 5.0+ (macOS default). macOS ships bash 3.2 which is too old — on macOS, `install.sh` detects this and re-execs under `zsh` if needed. Scripts must not use bash 4.3+ features (`nameref`, `${var@Q}`, `mapfile -d`). Use `read` loops and simple arrays only.

---

## Repository Layout

```
dot/
├── spec.md                  # This file
├── install.sh               # Single-command bootstrap entry point
├── setup/
│   ├── detect.sh            # OS/shell/tool detection helpers
│   ├── packages.sh          # Package installation (brew, apt, etc.)
│   ├── link.sh              # Symlink manager (backup, link, idempotent)
│   ├── terminfo.sh          # Ghostty terminfo compilation & distribution
│   └── post-install.sh      # Final steps (shell change, cache builds, etc.)
├── shell/
│   ├── env.sh               # POSIX env vars (PATH, EDITOR, COLORTERM, etc.)
│   ├── aliases.sh           # POSIX aliases shared by bash and zsh
│   ├── bashrc               # Bash-specific config, sources env.sh + aliases.sh
│   ├── zshrc                # Zsh-specific config, sources env.sh + aliases.sh
│   ├── zprofile             # Zsh login shell setup
│   ├── bash_profile         # Bash login shell setup
│   └── prompt.sh            # Built-in prompt (no external dependencies)
├── git/
│   ├── gitconfig.template   # Git config — [user] added on local, omitted on remote
│   └── gitignore_global     # Global gitignore patterns
├── tmux/
│   └── tmux.conf            # tmux configuration
├── ghostty/
│   └── config               # Ghostty terminal config (macOS only, not linked on remote)
├── zed/
│   └── settings.json        # Zed editor settings (macOS only)
├── claude/
│   └── settings.json        # Claude Code settings & statusline (always install latest version)
├── terminfo/
│   └── xterm-ghostty.terminfo  # Ghostty terminfo source for remote hosts
└── bin/
    ├── dot-push             # Push dotfiles to a remote host via scp+ssh
    ├── dot-ssh              # SSH with credentials forwarded via env, attaches tmux
    └── dot-update           # Git pull + re-run setup
```

---

## Bootstrap Flow

### Local (macOS)

```bash
git clone <repo> ~/dot && ~/dot/install.sh
```

### Remote (ephemeral host)

From local machine:
```bash
dot-push user@host
dot-push user@host --minimal    # Configs + terminfo only, no packages
dot-push user@host --no-claude  # Skip Claude Code install

# Then connect with credentials forwarded:
dot-ssh user@host               # Attaches tmux, forwards git/gh/aws creds
dot-ssh user@host --no-tmux     # Shell only, no tmux
```

On the remote host itself (if repo is already there):
```bash
~/dot/install.sh
```

### What `install.sh` does

All scripts use `set -euo pipefail`. Each phase is wrapped in a function that traps errors and reports status. A failed phase logs the error and continues to the next phase (except `detect.sh`, which is fatal).

1. Source `setup/detect.sh` — determine OS, distro, shell, package manager, whether inside SSH, whether tmux is available, whether sudo is available.
2. Run `setup/packages.sh` — install missing packages appropriate to the platform. **Skipped with `--minimal`.**
3. Run `setup/terminfo.sh` — compile and install ghostty terminfo if missing.
4. Run `setup/link.sh` — create parent directories (`mkdir -p`), then symlink config files to their expected locations, backing up any existing files.
5. Run `setup/post-install.sh` — any final steps (e.g., change default shell to zsh if available and not already set).
6. Write `~/dot/.version` with git SHA (if in a git repo) or timestamp (if pushed via tarball).
7. Print summary: what was installed, linked, skipped, and any errors encountered.

### `--dry-run` mode

All phases support `--dry-run`, which prints what would happen without making changes:
- Packages that would be installed
- Symlinks that would be created/replaced
- Files that would be backed up
- Terminfo that would be compiled

```bash
~/dot/install.sh --dry-run
dot-push user@host --dry-run
```

---

## Error Handling Strategy

- All scripts begin with `set -euo pipefail`.
- Each setup phase runs in a subshell or function with `trap` to catch failures.
- **`detect.sh` failure is fatal** — if we can't determine the OS, we can't proceed.
- **`packages.sh` failure is non-fatal** — log what failed, continue to linking. Missing packages are reported in the final summary.
- **`link.sh` failure is non-fatal per-link** — each symlink operation is independent. A failed link logs and continues.
- **`terminfo.sh` failure is non-fatal** — TERM falls back to `xterm-256color`.
- Exit code: 0 if all phases succeeded, 1 if any phase had errors (even if non-fatal). Summary distinguishes warnings from errors.

### Sudo Handling

- Detect sudo availability: check if `sudo` exists and user has passwordless sudo, or is already root.
- If sudo is required (package installs) but unavailable: skip package installation, log a warning, continue with config linking.
- Never prompt for a sudo password non-interactively. If `--interactive` is not set, skip packages that need sudo.

---

## Shell Architecture

### The Problem

Some hosts have zsh, some only bash. Aliases and env vars shouldn't be duplicated.

### The Solution

```
~/.bashrc   →  sources shell/env.sh + shell/aliases.sh + bash-specific setup
~/.zshrc    →  sources shell/env.sh + shell/aliases.sh + zsh-specific setup
```

**`shell/env.sh`** (POSIX):
- PATH construction (deduplicated, order-preserving)
- EDITOR, VISUAL, PAGER
- COLORTERM=truecolor, CLICOLOR=1, LSCOLORS
- TERM handling (see Terminal section) — **must be the first thing evaluated**, before any command that reads terminfo
- Homebrew shellenv (macOS only, detected)
- Go, npm, local bin paths

**`shell/aliases.sh`** (POSIX):
- Navigation: `..`, `...`, `....`
- Listing: `ll`, `la`, `l` (using `ls --color` on Linux, `ls -G` on macOS; `eza` if available)
- Git shortcuts: `gs`, `gd`, `gl`, `gco`, `gcm`, `gp`, `ga`
- Tmux: `ta` (attach or create), `tl` (list), `tk` (kill)
- Claude: `cc` (claude), `ccc` (claude --continue)
- Grep: `grep --color=auto`
- Safety: `rm -i`, `mv -i`, `cp -i` (interactive prompts on destructive ops)
- Platform-conditional aliases (e.g., `pbcopy`/`xclip`)
- `fd` normalization: alias `fd=fdfind` on Debian/Ubuntu where the binary is named differently

**`shell/zshrc`** (zsh-specific):
- History config (HISTSIZE, dedup, shared)
- Completion system (compinit, menu select, case-insensitive)
- Key bindings (emacs mode, history search)
- Source `prompt.sh` for prompt setup
- Auto-cd, correction, no beep

**`shell/bashrc`** (bash-specific):
- History config (HISTSIZE, dedup, append)
- Completion (bash-completion if available)
- Source `prompt.sh` for prompt setup
- Key bindings (history search)

**`shell/bash_profile`**:
- Sources `~/.profile` if it exists (preserves system-level PATH and `/etc/profile.d/` setup)
- Then sources `~/.bashrc`

**`shell/prompt.sh`** (the prompt — no external dependencies):
- Colorized PS1 with user, host (red `[SSH]` badge when remote), abbreviated cwd, git branch
- Works in both bash and zsh
- Lightweight — no subshells or external commands in the hot path
- Git branch via direct `.git/HEAD` read, not `git` subprocess
- Colors: green user@host, cyan cwd, magenta git branch, red SSH indicator

### Local Overrides

`~/.local.sh` is created by `post-install.sh` on first run with an empty template. It is **never overwritten** on subsequent runs. Both `bashrc` and `zshrc` source it at the end.

Shell-specific overrides are also supported:
- `~/.local.zsh` — zsh-specific overrides (only from zshrc)
- `~/.local.bash` — bash-specific overrides (only from bashrc)

Use these for:
- Extra PATH entries (e.g., LM Studio, OrbStack)
- Machine-specific aliases
- API keys / tokens (never in the repo)
- Tool integrations that vary per machine

---

## Terminal & Terminfo Strategy

### The Problem

Ghostty uses `TERM=xterm-ghostty`, but remote hosts don't have that terminfo entry. This breaks colors, cursor handling, and features through the chain: **Ghostty → SSH → tmux → shell/claude-code**.

### The Solution

1. **Ship the terminfo source** in `terminfo/xterm-ghostty.terminfo`.
2. **`setup/terminfo.sh`** compiles it with `tic` into `~/.terminfo/` on every host. Uses `tic -x` for extended capabilities on systems that support it; falls back to `tic` without `-x` on older ncurses (5.x). Verifies compilation succeeded by checking the output file exists.
3. **tmux.conf** sets `default-terminal "tmux-256color"` and configures both `terminal-overrides` and `terminal-features` for true color, undercurl, and extended keys.
4. **`shell/env.sh`** handles TERM negotiation **as the very first thing**, before any command that reads terminfo:
   - Inside tmux → trust tmux's TERM (`tmux-256color`), do not override
   - If `$TERM` is set and terminfo exists for it → keep it
   - If `$TERM` is set but terminfo is missing → fall back to `xterm-256color`
   - This prevents terminfo warning spam between SSH login and tmux attach
5. **COLORTERM=truecolor** is always exported.

### Validation

The setup script prints a color test grid after install to confirm:
- 256-color support
- True color (24-bit) support
- Bold, italic, underline rendering

(Undercurl validation only inside tmux with proper terminal-overrides configured.)

---

## tmux Configuration

```
# Terminal — base terminal type
set -g default-terminal "tmux-256color"

# True color support
set -ga terminal-overrides ",xterm-ghostty:Tc"
set -ga terminal-overrides ",xterm-256color:Tc"

# Undercurl support (colored underlines)
set -as terminal-overrides ',*:Smulx=\E[4::%p1%dm'
set -as terminal-overrides ',*:Setulc=\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'

# Extended features for tmux 3.2+ (ignored silently on older versions)
set -gq terminal-features ",xterm-ghostty:256:RGB:mouse:cstyle:overline:strikethrough:usstyle"
set -gq terminal-features ",xterm-256color:256:RGB"

# General
set -g mouse on
set -g history-limit 50000
set -g escape-time 10         # Low but not zero — safe over SSH latency
set -g focus-events on
set -g set-clipboard on

# Prefix
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# Window/pane management
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind c new-window -c "#{pane_current_path}"

# Vi-style pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Status bar
set -g status-style "bg=default,fg=green"
set -g status-left "#[bold]#S "
set -g status-right "#H %H:%M"

# Reload
bind r source-file ~/.tmux.conf \; display "Reloaded"
```

---

## Vim

No custom vimrc. Use stock vim. Users who want customization can add it via `~/.local.sh` or create their own `~/.vimrc` — it won't be managed or overwritten by this project.

---

## Package Management

### Detection Order

| OS | Package Manager | Install Method |
|---|---|---|
| macOS | Homebrew | Install brew if missing, then `brew install` |
| Debian/Ubuntu | apt | `sudo apt update && sudo apt install` |
| RHEL/Fedora/Amazon Linux | dnf/yum | `sudo dnf install` or `sudo yum install` |
| Alpine | apk | `sudo apk add` |
| Arch | pacman | `sudo pacman -S` |

**Sudo handling:** If user is root, run package commands directly. If sudo is available, use it. If neither, skip package installation and warn.

### Snap Cleanup (Ubuntu)

On Ubuntu systems, snap packages of core tools (e.g., `lxd`, `core18`, old `cmake`) can shadow or conflict with apt versions. `packages.sh` detects snap-installed versions of packages we manage and:
1. Removes the snap version (`sudo snap remove <pkg>`)
2. Installs the apt version instead
3. Logs what was replaced

This ensures we get current apt-managed versions rather than stale snaps.

### Package Name Mapping

Package names vary across distros. `packages.sh` maintains a mapping:

| Logical Name | apt | dnf/yum | apk | pacman | brew |
|---|---|---|---|---|---|
| fd | fd-find | fd-find | fd | fd | fd |
| ripgrep | ripgrep | ripgrep | ripgrep | ripgrep | ripgrep |
| bat | bat | bat | bat | bat | bat |

On Debian/Ubuntu where `fd` installs as `fdfind`, `aliases.sh` creates `alias fd=fdfind`.

### Packages to Install

**Core (all platforms):**
- `git` (if not present or too old)
- `tmux` — **must be nightly/HEAD build** (see Principle 5). `packages.sh` checks the installed version; if it lacks required patches, it builds tmux from the nightly source tarball (requires `libevent-dev`, `ncurses-dev`, `build-essential` or equivalents, installed automatically).
- `vim` (stock, no custom config)
- `curl`, `wget`
- `jq`, `unzip`
- `ripgrep` (`rg`)
- `fd` (or `fd-find`)
- `eza` (modern ls — optional, skipped if not in repos, aliases fall back to plain ls)

**macOS only:**
- Homebrew itself (if missing)
- `ghostty` (if not already installed)

**Optional:**
- `eza` — Only installed if available in the host's package repos. Never installed from source or curl. Aliases fall back to plain `ls` if unavailable.

**GitHub CLI (`gh`):**
- Always installed/updated to latest.
- On apt: adds GitHub's official apt repo for latest version (distro repos have stale versions).
- On dnf/yum: adds GitHub's rpm repo.
- On apk: `github-cli` from Alpine repos.
- On pacman: `github-cli` from Arch repos.
- On brew: `brew install gh`.
- Credentials are not stored on disk — `GH_TOKEN` is forwarded by `dot-ssh` at connection time.

**AWS CLI:**
- Always installed/updated.
- On glibc Linux (Ubuntu, Debian, RHEL, Fedora, Amazon Linux, Arch): AWS CLI v2 from official zip installer at `awscli.amazonaws.com`. Supports x86_64 and aarch64.
- On Alpine (musl): AWS CLI v1 via `pip install awscli` (the v2 zip requires glibc).
- On macOS: `brew install awscli`.
- Credentials are not stored on disk — `AWS_*` env vars are forwarded by `dot-ssh` at connection time.

**Claude Code:**
- Detect if `claude` is already on PATH → done.
- If not, and `--no-claude` is passed → skip.
- If not, and `node`/`npm` are on PATH → `npm install -g @anthropic-ai/claude-code@latest`.
- If node is missing → install node via package manager, then install claude.
- If claude is already installed → `npm update -g @anthropic-ai/claude-code` to ensure latest version.
- **On `--minimal` installs: always skipped.**

---

## Symlink Strategy

`setup/link.sh` manages all symlinks.

**Before linking:** `mkdir -p` for all target parent directories:
- `~/.config/`
- `~/.config/ghostty/`
- `~/.config/zed/`
- `~/.claude/`
- `~/.dotfiles-backup/`

| Source (in repo) | Target (on filesystem) | Condition |
|---|---|---|
| `shell/bashrc` | `~/.bashrc` | always |
| `shell/bash_profile` | `~/.bash_profile` | always |
| `shell/zshrc` | `~/.zshrc` | zsh installed |
| `shell/zprofile` | `~/.zprofile` | zsh installed |
| (generated) `~/.gitconfig` | `~/.gitconfig` | always (see Git section) |
| `git/gitignore_global` | `~/.gitignore_global` | always |
| `tmux/tmux.conf` | `~/.tmux.conf` | always |
| `ghostty/config` | `~/.config/ghostty/config` | macOS only |
| `zed/settings.json` | `~/.config/zed/settings.json` | macOS only |
| `claude/settings.json` | `~/.claude/settings.json` | claude installed |

**Symlink method:** Use `ln -sfn` for atomic replacement (creates link to temp name, then `mv` on platforms where `ln -sfn` is not atomic). No window where neither old nor new file exists.

**Backup behavior:**
- If target exists and is a regular file (not a symlink to our source) → move to `~/.dotfiles-backup/<filename>.<timestamp>`
- If target is already correctly linked → skip (idempotent)
- If target is a symlink to something else → log what it pointed to, then replace

**Stale symlink cleanup:** After linking, scan `~/` for symlinks pointing into `~/dot/` that no longer resolve. Report them. Do not auto-delete (user may have renamed files intentionally).

---

## Git Configuration

`git/gitconfig.template` is generated into `~/.gitconfig` during install (not symlinked). The template contains `[core]`, `[init]`, `[pull]`, `[push]`, `[filter "lfs"]`, `[alias]`, and `[url]` sections.

**Local installs:** A `[user]` section with name/email is prepended to the generated config. Identity is read from the existing `~/.gitconfig` (before backup) or global git config, or prompted interactively. This ensures `git commit` works without environment variable injection.

**Remote installs (`--remote`):** No `[user]` section. Git identity comes entirely from environment variables (`GIT_AUTHOR_NAME`, etc.) forwarded by `dot-ssh` at connection time. Nothing on disk. The `[url]` SSH rewrite is also stripped, since SSH agent forwarding + `GH_TOKEN` handle auth.

---

## Credential Forwarding (`dot-ssh`)

**No secrets are ever written to disk on remote hosts.** All credentials live in the process environment only.

`dot-ssh user@host` connects via `ssh -A -t`, injecting env vars inline in the remote command, then attaches tmux. tmux's `update-environment` re-imports fresh values on every attach.

**Forwarded credentials:**

| Variable | Source | Used by |
|---|---|---|
| `GIT_AUTHOR_NAME` / `_EMAIL` | local `git config` | git commits |
| `GIT_COMMITTER_NAME` / `_EMAIL` | local `git config` | git commits |
| `GH_TOKEN` | `gh auth token` | gh CLI, git credential helper |
| `AWS_ACCESS_KEY_ID` | local env | aws CLI, SDKs |
| `AWS_SECRET_ACCESS_KEY` | local env | aws CLI, SDKs |
| `AWS_SESSION_TOKEN` | local env | aws CLI (STS) |
| `AWS_PROFILE` | local env | aws CLI |
| `AWS_REGION` / `AWS_DEFAULT_REGION` | local env | aws CLI, SDKs |
| `SSH_AUTH_SOCK` | SSH agent (`-A`) | git-over-SSH |

**tmux propagation:** `tmux.conf` lists all credential vars in `update-environment`. New panes/windows inherit from tmux server. Re-attach via `dot-ssh` refreshes all values. Claude Code runs inside tmux panes and inherits everything.

### `git/gitignore_global`

```gitignore
.DS_Store
*.swp
*.swo
*~
.env
.env.local
.idea/
.vscode/
__pycache__/
*.pyc
node_modules/
.direnv/
```

---

## Remote Push Workflow (`dot-push`)

```bash
dot-push user@host [--minimal] [--no-claude] [--dry-run]
```

1. Create a tarball of the repo excluding:
   - `.git/`
   - `ghostty/`
   - `zed/`
   - `spec.md`
   - `.DS_Store`
2. `scp` tarball to remote `~/dot.tar.gz`.
3. `ssh` into host:
   - Extract to `~/dot/`
   - Run `~/dot/install.sh --remote [--minimal] [--no-claude]`
   - Clean up tarball
   - Write `~/dot/.version` with local git SHA + timestamp
4. Print summary of what was installed/linked.

### `--minimal` mode

Configs + terminfo only. No package installation, no Claude Code. This is the fastest path — useful for hosts where you just need your shell config and colors working.

### Typical workflow

```bash
dot-push user@host              # Push configs + install packages (once)
dot-ssh user@host               # Connect with credentials (every time)
```

`dot-push` sets up the host. `dot-ssh` connects with credentials. Use `dot-ssh` for all subsequent connections — it forwards git identity, GH token, AWS creds, and SSH agent. Never use plain `ssh` to connect if you need credentials.

---

## Update Workflow

### On a machine with git access:
```bash
dot-update
# Equivalent to: cd ~/dot && git pull && ./install.sh
```

### On an ephemeral remote (no git):
```bash
# From local machine:
dot-push user@host
```

### Version tracking

`~/dot/.version` contains the git SHA (or timestamp) of the deployed version. `dot-push` compares local vs remote version before pushing and shows a diff summary of what changed.

---

## What This Project Does NOT Include

- **SSH keys or secrets** — Never committed. Per-host SSH config goes in `~/.local.sh` or host-specific `~/.ssh/config`.
- **Plugin managers** — No oh-my-zsh, no vim plugin managers. Keep it lean for ephemeral hosts.
- **Desktop environment config** — No window manager, dock, keyboard, etc. Only terminal-centric tools.
- **Encrypted secrets** — No age/gpg integration. Secrets are managed out of band.
- **Uninstall** — On ephemeral hosts this is unnecessary. Backups in `~/.dotfiles-backup/` allow manual restoration.

---

## Testing

A `test/` directory (not deployed to remotes) contains Dockerfiles for each target platform:

```
test/
├── Dockerfile.ubuntu18
├── Dockerfile.ubuntu22
├── Dockerfile.amazonlinux2
├── Dockerfile.amazonlinux2023
├── Dockerfile.rhel7
├── Dockerfile.alpine
└── run-tests.sh
```

`run-tests.sh` builds each image, runs `install.sh`, and verifies:
- Symlinks are correct
- Shell sources without errors
- TERM/COLORTERM are set correctly
- Terminfo is compiled
- Aliases resolve
- Git config is generated
- No bash 4.3+ features used (shellcheck with `--shell=bash` and version target)

---

## Resolved Decisions

- **tmux plugins** — No plugin manager. Keep tmux config self-contained.
- **Zed remote** — Zed handles its own remote server binary on first connect. We don't manage it.
- **Claude Code settings** — Ship a default `~/.claude/settings.json` with statusline config.
- **Starship** — Dropped. Use a simple built-in prompt (`prompt.sh`) with no external dependencies.
- **Vim config** — Use stock vim. No managed vimrc.
- **Git identity** — Local: `[user]` in gitconfig, preserved across re-runs. Remote: env vars (`GIT_AUTHOR_NAME`, etc.) forwarded by `dot-ssh`, no `[user]` in gitconfig.
- **Credentials** — All forwarded via `dot-ssh` environment injection + tmux `update-environment`. Never written to disk. Covers git identity, GH token, AWS credentials, SSH agent.
- **GitHub CLI** — Installed from official repos. Auth via `GH_TOKEN` env var.
- **AWS CLI** — v2 from official installer (glibc Linux), v1 via pip (Alpine/musl), brew (macOS).
