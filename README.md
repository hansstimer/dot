# dot

Cross-platform dotfiles for macOS and Linux. One command to install locally, one command to push to a remote host.

Built for ephemeral remote hosts where you SSH in, need your shell working properly, and don't want to spend 20 minutes configuring things.

## Quick Start

### Local (macOS)

```bash
git clone <repo> ~/dot && ~/dot/install.sh
```

### Remote host

```bash
# From your local machine — push configs + install packages
dot-push user@host

# Just configs, no package installs (fast)
dot-push user@host --minimal

# Skip Claude Code
dot-push user@host --no-claude
```

### Connect with credentials

```bash
# SSH in with git identity, GH token, and SSH agent forwarded
# Drops you into a tmux session — all panes inherit credentials
dot-ssh user@host

# Without tmux
dot-ssh user@host --no-tmux
```

`dot-ssh` reads your local `git config`, `gh auth token`, and AWS env vars, injects them as environment variables, and forwards your SSH agent. Nothing is written to disk on the remote. tmux's `update-environment` re-imports them on every attach, so credentials stay fresh.

### Update

```bash
# Local (git pull + re-run install)
dot-update

# Remote (re-push from local)
dot-push user@host
```

## What It Does

- Detects OS, distro, package manager, shell, sudo — configures accordingly
- Links shell configs (bashrc/zshrc), tmux.conf, gitconfig, gitignore
- Compiles Ghostty terminfo so `TERM=xterm-ghostty` works over SSH
- Builds tmux from nightly source (has Claude Code fixes not yet released)
- Installs core tools: git, vim, curl, jq, ripgrep, fd, unzip
- Installs/updates GitHub CLI (`gh`) from official repos
- Installs/updates AWS CLI v2 (v1 via pip on Alpine)
- Installs/updates Claude Code to latest
- Sets up a colorized prompt that works in both bash and zsh with no dependencies
- Handles TERM negotiation: keeps `xterm-ghostty` when terminfo exists, falls back to `xterm-256color` when it doesn't — no more terminfo warnings

## What's In the Box

```
shell/env.sh          Shared env vars, PATH, TERM negotiation
shell/aliases.sh      Shared aliases (git, tmux, navigation, claude)
shell/prompt.sh       Built-in prompt — git branch, SSH badge, colors
shell/bashrc          Bash config — sources the above
shell/zshrc           Zsh config — sources the above
tmux/tmux.conf        True color, undercurl, escape-time 10, C-a prefix, credential forwarding
git/gitconfig.template    No [user] section — identity via env vars from dot-ssh
ghostty/config        Ghostty terminal config (macOS only)
zed/settings.json     Zed editor settings (macOS only)
claude/settings.json  Claude Code statusline config
```

## Install Modes

| Flag | What it does |
|---|---|
| (none) | Full install — packages, configs, terminfo |
| `--remote` | Skip macOS-only configs, strip git SSH URL rewrite |
| `--minimal` | Configs + terminfo only, no packages at all |
| `--no-claude` | Skip Claude Code install/update |
| `--dry-run` | Print what would happen, change nothing |

Flags combine: `install.sh --remote --minimal --no-claude --dry-run`

## Shell Aliases

| Alias | Command |
|---|---|
| `..` / `...` / `....` | `cd ..` / `../..` / `../../..` |
| `ll` | `ls -lAh` (or `eza -lah` if available) |
| `gs` | `git status -sb` |
| `gd` / `gdc` | `git diff` / `git diff --cached` |
| `gl` / `glg` | `git log --oneline -20` / with graph |
| `gco` / `gcm` / `gp` / `ga` | checkout / commit -m / push / add |
| `ta` | `tmux attach -t main` (or create) |
| `tl` / `tk` | tmux list / kill |
| `cc` / `ccc` | `claude` / `claude --continue` |

## Local Overrides

Drop these files in your home directory for per-machine customization:

- `~/.local.sh` — sourced by both bash and zsh
- `~/.local.bash` — sourced by bash only
- `~/.local.zsh` — sourced by zsh only

Use them for API keys, extra PATH entries, work-specific aliases. Never committed.

## Terminal Chain

The full chain **Ghostty → SSH → tmux → shell** works correctly:

1. Ghostty sets `TERM=xterm-ghostty`
2. SSH passes it to the remote host
3. `env.sh` checks terminfo exists (we compiled it), keeps it
4. tmux runs with `default-terminal "tmux-256color"` + true color overrides
5. Inside tmux, `TERM=tmux-256color` with `COLORTERM=truecolor`
6. Colors, italic, bold, underline, undercurl all work

If terminfo is missing (install hasn't run yet), `env.sh` silently falls back to `xterm-256color`. No warnings, no breakage.

## Credentials

No tokens or secrets are ever written to disk on remote hosts.

**Git identity** — `dot-ssh` forwards `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL` from your local git config. Git reads these from the environment.

**GitHub CLI** — `dot-ssh` forwards `GH_TOKEN` from `gh auth token`. The `gh` CLI and any tool that reads `GH_TOKEN` works immediately. `gh` is installed on remote hosts from official repos.

**AWS CLI** — `dot-ssh` forwards `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`, and `AWS_REGION` from your local environment. AWS CLI v2 is installed on remote hosts.

**SSH agent** — `dot-ssh` uses `ssh -A` to forward your SSH agent. Git-over-SSH operations work.

**tmux propagation** — `tmux.conf` has `update-environment` configured for all credential env vars (git, gh, AWS, SSH). When you attach a tmux session via `dot-ssh`, tmux re-imports the fresh values from your SSH session. Every new pane and window inherits them.

**gitconfig** — The generated `~/.gitconfig` has no `[user]` section. Identity comes entirely from environment. On `--remote` installs, the `[url]` SSH rewrite is also stripped since agent forwarding handles SSH auth and `GH_TOKEN` handles HTTPS.

**Claude Code** — runs inside tmux panes, inherits all of the above. `gh pr create`, `git push`, `aws s3 ls`, etc. all work from within Claude.

## Requirements

- **Local (macOS):** zsh (default shell), Homebrew (installed automatically if missing)
- **Remote (Linux):** bash 4.2+ (RHEL 7 / Amazon Linux 2 era), curl, git
- **To push:** SSH access to the remote host

## Testing

```bash
# Run against Ubuntu and Alpine containers
bash test/run-tests.sh
```

Requires Docker. Tests install, symlinks, terminfo compilation, TERM negotiation, shell sourcing, aliases, git config, idempotency.
