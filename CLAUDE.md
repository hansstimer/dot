# dot — Agent Reference

Cross-platform dotfiles repo. Configs macOS + Linux (ephemeral remote hosts). Bash 4.2+ and zsh 5.0+ compatible. No external prompt tools (no starship), no vim plugins, no oh-my-zsh.

## Architecture

```
install.sh                 Entry point. Parses flags, runs phases in order.
  ├── setup/detect.sh      Sources into install.sh. Sets DOT_* env vars.
  ├── setup/packages.sh    Standalone. Installs packages, builds tmux, gh, aws, claude.
  ├── setup/terminfo.sh    Standalone. Compiles xterm-ghostty terminfo.
  ├── setup/link.sh        Standalone. Symlinks configs, generates gitconfig.
  └── setup/post-install.sh  Standalone. Writes .version, prints color test.

shell/env.sh               Sourced by bashrc/zshrc. TERM negotiation + PATH + env.
shell/aliases.sh           Sourced by bashrc/zshrc. Shared aliases.
shell/prompt.sh            Sourced by bashrc/zshrc. Git-aware prompt, no dependencies.
shell/bashrc               → sources env.sh, aliases.sh, prompt.sh, ~/.local.sh, ~/.local.bash
shell/zshrc                → sources env.sh, aliases.sh, prompt.sh, ~/.local.sh, ~/.local.zsh
shell/bash_profile         → sources ~/.profile then ~/.bashrc
shell/zprofile             → Homebrew shellenv (macOS only)

bin/dot-push               Push configs to remote, run install. No secrets written.
bin/dot-ssh                SSH with credentials forwarded via env. Attaches tmux.
bin/dot-update             Git pull + re-run install.
```

## Key Environment Variables

Set by `setup/detect.sh`, exported, available to all phases:

| Variable | Values | Description |
|---|---|---|
| `DOT_DIR` | `/home/user/dot` | Repo root. Set by install.sh. |
| `DOT_OS` | `macos`, `linux` | Operating system |
| `DOT_DISTRO` | `ubuntu`, `alpine`, `amzn`, `fedora`, etc. | Linux distribution ID |
| `DOT_PKG_MGR` | `apt`, `dnf`, `yum`, `apk`, `pacman`, `brew` | Package manager |
| `DOT_HAS_ZSH` | `true`/`false` | Zsh available |
| `DOT_HAS_BASH` | `true`/`false` | Bash available |
| `DOT_HAS_SUDO` | `true`/`false` | Passwordless sudo or root |
| `DOT_IS_ROOT` | `true`/`false` | Running as UID 0 |
| `DOT_IS_SSH` | `true`/`false` | Inside SSH session |
| `DOT_HAS_TMUX` | `true`/`false` | tmux binary found |
| `DOT_HAS_CLAUDE` | `true`/`false` | claude binary found |
| `DOT_HAS_TIC` | `true`/`false` | tic (terminfo compiler) found |
| `DOT_IS_INTERACTIVE` | `true`/`false` | stdin and stdout are TTYs |
| `DOT_REMOTE` | `true`/`false` | `--remote` flag passed |
| `DOT_MINIMAL` | `true`/`false` | `--minimal` flag passed |
| `DOT_DRY_RUN` | `true`/`false` | `--dry-run` flag passed |
| `DOT_NO_CLAUDE` | `true`/`false` | `--no-claude` flag passed |

## Install Phases

Phases run in order. Each is a separate script sourced in a subshell.

1. **detect** (fatal) — Sets all `DOT_*` variables. If this fails, install aborts.
2. **packages** (non-fatal, skipped with `--minimal`) — Installs core tools, gh (from official repos), AWS CLI v2, builds tmux from nightly source, installs Claude Code.
3. **terminfo** (non-fatal) — Compiles `xterm-ghostty` into `~/.terminfo/`. Falls back silently.
4. **link** (non-fatal per-link) — Creates symlinks, generates gitconfig, backs up existing files.
5. **post-install** (non-fatal) — Writes `.version`, runs color test.

Error handling: `set -euo pipefail` everywhere. Each phase catches its own errors. A non-fatal phase failure increments `PHASE_ERRORS` and continues. Exit code is 1 if any phase had errors.

## Symlink Table

Managed by `setup/link.sh`. Uses `ln -sfn` for atomic replacement.

| Source | Target | Condition |
|---|---|---|
| `shell/bashrc` | `~/.bashrc` | always |
| `shell/bash_profile` | `~/.bash_profile` | always |
| `shell/zshrc` | `~/.zshrc` | zsh installed |
| `shell/zprofile` | `~/.zprofile` | zsh installed |
| `git/gitignore_global` | `~/.gitignore_global` | always |
| `tmux/tmux.conf` | `~/.tmux.conf` | always |
| `ghostty/config` | `~/.config/ghostty/config` | macOS only |
| `zed/settings.json` | `~/.config/zed/settings.json` | macOS only |
| `claude/settings.json` | `~/.claude/settings.json` | claude installed |

`~/.gitconfig` is **generated** from `git/gitconfig.template` (not symlinked). On `--remote`, the SSH URL rewrite section is stripped.

## TERM Negotiation (shell/env.sh)

This is the most critical piece for terminal correctness. The logic, which runs **before any other command** in env.sh:

```
if inside tmux:
    do nothing (trust tmux's TERM, which is tmux-256color)
else if TERM is set and terminfo exists for it:
    keep it (e.g., xterm-ghostty stays xterm-ghostty)
else if TERM is set but terminfo is missing:
    fall back to xterm-256color
else if TERM is unset:
    set to xterm-256color
```

The `_dot_has_terminfo()` function checks via `infocmp` first, then falls back to filesystem checks in `~/.terminfo/`, `/usr/share/terminfo/`, `/usr/lib/terminfo/`, `/etc/terminfo/`. Terminfo entries are stored under either the first character or hex value of the first character (e.g., `x/xterm-ghostty` or `78/xterm-ghostty`).

`COLORTERM=truecolor` is always exported regardless of TERM.

## tmux Configuration

Key settings in `tmux/tmux.conf`:

- `default-terminal "tmux-256color"` — what tmux reports as TERM inside panes
- `terminal-overrides` for Tc (true color), Smulx (undercurl style), Setulc (undercurl color)
- `terminal-features` for tmux 3.2+ (RGB, mouse, cursor style, underline style)
- `escape-time 10` — not zero, safe over SSH latency
- `prefix C-a` — rebound from default C-b
- Vi-style pane nav: `h/j/k/l`
- `|` and `-` for splits
- `update-environment` — re-imports credential env vars from attaching client on each `tmux attach`

## Credential Forwarding (bin/dot-ssh)

**No secrets are ever written to disk on remote hosts.** All credentials live in the process environment only.

`dot-ssh user@host` does:
1. Reads local `git config user.name` / `user.email` → sets `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL`
2. Reads local `gh auth token` → sets `GH_TOKEN`
3. Reads local AWS env vars → forwards `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`, `AWS_REGION`, `AWS_DEFAULT_REGION`
4. SSH with `-A` (agent forwarding) and `-t` (force TTY)
5. Injects all env vars inline in the remote command: `GIT_AUTHOR_NAME='...' GH_TOKEN='...' AWS_ACCESS_KEY_ID='...' tmux new-session -As main`
6. tmux's `update-environment` captures these vars from the attaching client

**How it propagates through tmux:**
- First attach: tmux server starts with the env vars from dot-ssh
- New panes/windows: inherit from tmux server's environment
- Re-attach (after detach): `update-environment` re-imports fresh values from the new SSH session
- Claude Code, gh, git, aws: all run inside tmux panes, inherit everything

**Forwarded env vars (full list):**

| Variable | Source | Used by |
|---|---|---|
| `GIT_AUTHOR_NAME` | `git config user.name` | git |
| `GIT_AUTHOR_EMAIL` | `git config user.email` | git |
| `GIT_COMMITTER_NAME` | `git config user.name` | git |
| `GIT_COMMITTER_EMAIL` | `git config user.email` | git |
| `GH_TOKEN` | `gh auth token` | gh, git credential helper |
| `GITHUB_TOKEN` | (tmux update-environment) | GitHub Actions compat |
| `AWS_ACCESS_KEY_ID` | local env | aws cli, SDKs |
| `AWS_SECRET_ACCESS_KEY` | local env | aws cli, SDKs |
| `AWS_SESSION_TOKEN` | local env | aws cli (STS sessions) |
| `AWS_PROFILE` | local env | aws cli |
| `AWS_REGION` | local env | aws cli, SDKs |
| `AWS_DEFAULT_REGION` | local env | aws cli, SDKs |
| `SSH_AUTH_SOCK` | SSH agent | git-over-SSH |
| `SSH_CONNECTION` | SSH session | prompt SSH badge |

**Git identity:** `~/.gitconfig` has no `[user]` section. Git reads identity from `GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL` in the environment.

**GitHub CLI:** `gh` reads `GH_TOKEN` from environment. Installed from official GitHub repos (latest on apt/dnf, distro version on Alpine/pacman). Works for `gh pr create`, `gh issue list`, etc.

**AWS CLI:** Installed as v2 from official installer on glibc Linux, v1 via pip on Alpine (musl). Reads credentials from `AWS_*` env vars forwarded by dot-ssh.

**Git SSH auth:** SSH agent forwarding (`-A`) handles `git push`/`git pull` over SSH protocol.

**Git HTTPS auth:** If `gh` is installed on the remote, `gh auth setup-git` can configure it as a credential helper that reads `GH_TOKEN`. This is not done automatically — run it manually if needed.

## Prompt (shell/prompt.sh)

No external dependencies. Works in both bash and zsh.

- **Zsh:** Uses `precmd` hook via `add-zsh-hook` to update git branch. PROMPT_SUBST enabled.
- **Bash:** Uses `PROMPT_COMMAND` to update git branch before each prompt.
- **Git branch:** Read directly from `.git/HEAD` file (walks up directory tree). No `git` subprocess. Shows branch name or short SHA if detached.
- **SSH detection:** Red `[SSH]` badge when `SSH_CLIENT`, `SSH_TTY`, or `SSH_CONNECTION` is set.
- **Colors:** Green user@host, cyan cwd, magenta git branch, yellow `❯` symbol.

## Adding a New Config File

1. Create the config file in its directory (e.g., `neovim/init.lua`).
2. Add the symlink entry in `setup/link.sh` in the `link_all()` function:
   ```bash
   do_link "$DOT_DIR/neovim/init.lua" "$HOME/.config/nvim/init.lua"
   ```
3. If the target needs a parent directory, add it to `ensure_dirs()`.
4. If it's macOS-only, wrap in `if [ "${DOT_OS:-}" = "macos" ]`.
5. If it's conditional on a tool, check with `command -v` or `DOT_HAS_*` variable.

## Adding a New Package

In `setup/packages.sh`:

1. **Simple packages** (available in standard repos): Add an `is_installed <binary>` check to the `core_pkgs` array in `install_packages()`. If the package name varies by distro, add a mapping in `pkg_name()`.
2. **Complex packages** (custom repos, source builds, or non-standard install): Create a dedicated `install_<name>()` function (see `install_gh`, `install_awscli`, `install_claude` as examples) and call it from `install_packages()`. Handle per-distro differences inside the function.
3. **Credential-bearing tools**: If the tool needs auth on the remote, add its env vars to `dot-ssh` (forwarding) and to tmux's `update-environment` in `tmux.conf`.

## Adding a New Alias

Add to `shell/aliases.sh`. Keep it POSIX-compatible (no bash/zsh-specific syntax). Platform-conditional aliases use `uname -s` checks or `command -v` guards.

## Testing

```bash
bash test/run-tests.sh          # Ubuntu + Alpine containers
```

Tests verify: symlinks, shell sourcing, terminfo compilation, TERM negotiation/fallback, git config generation, alias definitions, tmux config syntax, idempotency.

To test a single distro manually:

```bash
docker build -t dot-test -f test/Dockerfile.ubuntu .
docker run --rm -it dot-test bash
# Inside container:
cd ~/dot && bash install.sh --remote --minimal
```

## Bash Compatibility

Scripts target bash 4.2 (RHEL 7 / Amazon Linux 2). Do NOT use:
- `nameref` (`declare -n`)
- `${var@Q}` (parameter transformation)
- `mapfile -d` (delimiter option)
- `readarray` (use `read` loops instead)
- Associative arrays with complex operations (simple `declare -A` is OK in 4.2 but behavior varies)

On macOS, `install.sh` detects bash 3.2 and re-execs under `zsh`.

## File Locations After Install

| File | Type | Notes |
|---|---|---|
| `~/.bashrc` | symlink → `dot/shell/bashrc` | |
| `~/.bash_profile` | symlink → `dot/shell/bash_profile` | |
| `~/.zshrc` | symlink → `dot/shell/zshrc` | if zsh available |
| `~/.zprofile` | symlink → `dot/shell/zprofile` | if zsh available |
| `~/.gitconfig` | generated file | no [user] section — identity via env vars |
| `~/.gitignore_global` | symlink → `dot/git/gitignore_global` | |
| `~/.tmux.conf` | symlink → `dot/tmux/tmux.conf` | |
| `~/.config/ghostty/config` | symlink → `dot/ghostty/config` | macOS only |
| `~/.config/zed/settings.json` | symlink → `dot/zed/settings.json` | macOS only |
| `~/.claude/settings.json` | symlink → `dot/claude/settings.json` | if claude installed |
| `~/.terminfo/x/xterm-ghostty` | compiled binary | from terminfo source |
| `~/.dotfiles-backup/` | directory | backups of replaced files |
| `~/dot/.version` | text file | install timestamp + git SHA |

## Common Issues

**terminfo warnings on SSH login:** The terminfo compilation (`setup/terminfo.sh`) didn't run or failed. Check `~/.terminfo/x/xterm-ghostty` exists. Re-run `install.sh` or manually: `tic -x -o ~/.terminfo ~/dot/terminfo/xterm-ghostty.terminfo`

**Colors broken inside tmux:** Check `tmux show -gv default-terminal` returns `tmux-256color`. Check `tmux show -g terminal-overrides` includes the Tc entries. May need to kill all tmux sessions and restart after config change.

**Git clone fails on remote host:** The SSH URL rewrite (`[url]` section) may not have been stripped. Check `~/.gitconfig` — if it has `insteadOf = https://github.com/`, remove that section or re-run `install.sh --remote`.

**Prompt shows no git branch:** The `.git/HEAD` file read walks up from `$PWD`. If you're in a subdir of a bare repo or a worktree with unusual structure, it may not find it. The prompt degrades gracefully — it just shows no branch.

**tmux build fails:** Needs build dependencies (libevent-dev, ncurses-dev, build-essential/base-devel, autoconf, automake, bison). Check `packages.sh` output for which dependency failed to install.

**`gh` says "not logged in" on remote:** You connected with plain `ssh` instead of `dot-ssh`. The `GH_TOKEN` env var is only set by `dot-ssh`. Disconnect and reconnect via `dot-ssh user@host`.

**Git says "please tell me who you are" on remote:** Same cause — `GIT_AUTHOR_NAME` is only set by `dot-ssh`. The gitconfig has no `[user]` section by design.

**Credentials lost after tmux detach/reattach:** If you reattach via `dot-ssh`, `update-environment` re-imports fresh values. If you reattach via plain `tmux attach` (inside a regular SSH session), the old values remain but won't be refreshed. Always use `dot-ssh` to connect.

**`aws` command not found on Alpine:** pip installs to `~/.local/bin/aws`. This is on PATH via `env.sh`, but only after shell restart. Run `source ~/.bashrc` or start a new shell.

**AWS CLI v1 vs v2:** Alpine gets v1 (via pip, because the v2 official zip requires glibc). All other Linux distros get v2 (from the official installer). macOS gets v2 via Homebrew. Both support the same `AWS_*` env vars.
