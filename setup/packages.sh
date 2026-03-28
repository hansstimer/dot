#!/usr/bin/env bash
# packages.sh — Package installation (brew, apt, dnf, apk, pacman)
set -euo pipefail

DOT_DIR="${DOT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
DRY_RUN="${DOT_DRY_RUN:-false}"
NO_CLAUDE="${DOT_NO_CLAUDE:-false}"
PKG_ERRORS=0

# --- Helper: run with sudo if needed ---
as_root() {
    if [ "${DOT_IS_ROOT:-false}" = true ]; then
        "$@"
    elif [ "${DOT_HAS_SUDO:-false}" = true ]; then
        sudo "$@"
    else
        echo "  [WARN] Cannot run as root: $*"
        return 1
    fi
}

# --- Package name mapping ---
# Returns the distro-specific package name for a logical name
pkg_name() {
    local logical="$1"
    local mgr="${DOT_PKG_MGR:-unknown}"

    case "$logical" in
        fd)
            case "$mgr" in
                apt) echo "fd-find" ;;
                dnf|yum) echo "fd-find" ;;
                *) echo "fd" ;;
            esac
            ;;
        build-essential)
            case "$mgr" in
                apt) echo "build-essential" ;;
                dnf|yum) echo "gcc gcc-c++ make" ;;
                apk) echo "build-base" ;;
                pacman) echo "base-devel" ;;
                brew) echo "" ;;  # Xcode CLI tools handle this
            esac
            ;;
        libevent-dev)
            case "$mgr" in
                apt) echo "libevent-dev" ;;
                dnf|yum) echo "libevent-devel" ;;
                apk) echo "libevent-dev" ;;
                pacman) echo "libevent" ;;
                brew) echo "libevent" ;;
            esac
            ;;
        ncurses-dev)
            case "$mgr" in
                apt) echo "libncurses-dev" ;;
                dnf|yum) echo "ncurses-devel" ;;
                apk) echo "ncurses-dev" ;;
                pacman) echo "ncurses" ;;
                brew) echo "ncurses" ;;
            esac
            ;;
        bison)
            echo "bison"
            ;;
        *) echo "$logical" ;;
    esac
}

# --- Check if package is installed ---
is_installed() {
    command -v "$1" >/dev/null 2>&1
}

# --- Install packages via detected package manager ---
pkg_install() {
    local pkgs=("$@")
    if [ ${#pkgs[@]} -eq 0 ]; then return 0; fi

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would install: ${pkgs[*]}"
        return 0
    fi

    echo "  Installing: ${pkgs[*]}"
    case "${DOT_PKG_MGR:-unknown}" in
        apt)
            as_root apt-get install -y "${pkgs[@]}" 2>&1 | tail -1
            ;;
        dnf)
            as_root dnf install -y "${pkgs[@]}" 2>&1 | tail -1
            ;;
        yum)
            as_root yum install -y "${pkgs[@]}" 2>&1 | tail -1
            ;;
        apk)
            as_root apk add --no-cache "${pkgs[@]}" 2>&1 | tail -1
            ;;
        pacman)
            as_root pacman -S --noconfirm "${pkgs[@]}" 2>&1 | tail -1
            ;;
        brew)
            brew install "${pkgs[@]}" 2>&1 | tail -1
            ;;
        *)
            echo "  [WARN] Unknown package manager: ${DOT_PKG_MGR:-unknown}"
            return 1
            ;;
    esac
}

# --- Update package index ---
pkg_update() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would update package index"
        return 0
    fi

    echo "  Updating package index..."
    case "${DOT_PKG_MGR:-unknown}" in
        apt)
            as_root apt-get update -qq 2>&1 | tail -1
            ;;
        dnf|yum)
            # dnf/yum auto-refresh
            ;;
        apk)
            as_root apk update -q 2>&1 | tail -1
            ;;
        pacman)
            as_root pacman -Sy --noconfirm 2>&1 | tail -1
            ;;
        brew)
            brew update --quiet 2>&1 | tail -1
            ;;
    esac
}

# --- Snap cleanup (Ubuntu) ---
snap_cleanup() {
    if [ "${DOT_DISTRO:-}" != "ubuntu" ] && [ "${DOT_DISTRO:-}" != "debian" ]; then
        return 0
    fi
    if ! command -v snap >/dev/null 2>&1; then
        return 0
    fi

    echo "  Checking for conflicting snap packages..."
    # We only care about snaps that shadow tools we install
    local snap_pkgs
    snap_pkgs="$(snap list 2>/dev/null | awk 'NR>1 {print $1}' || true)"

    for pkg in cmake lxd; do
        if echo "$snap_pkgs" | grep -qw "$pkg"; then
            if [ "$DRY_RUN" = true ]; then
                echo "  [DRY-RUN] Would remove snap: $pkg"
            else
                echo "  [SNAP] Removing snap: $pkg"
                as_root snap remove "$pkg" 2>/dev/null || true
            fi
        fi
    done
}

# --- Build tmux from source (nightly) ---
build_tmux() {
    echo "  Building tmux from source (nightly)..."

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would build tmux from nightly source"
        return 0
    fi

    # Install build dependencies
    local build_deps=""
    for dep in build-essential libevent-dev ncurses-dev bison; do
        local mapped
        mapped="$(pkg_name "$dep")"
        if [ -n "$mapped" ]; then
            build_deps="$build_deps $mapped"
        fi
    done

    # Also need git, autoconf, automake for nightly
    case "${DOT_PKG_MGR:-}" in
        apt) build_deps="$build_deps autoconf automake pkg-config" ;;
        dnf|yum) build_deps="$build_deps autoconf automake pkgconfig" ;;
        apk) build_deps="$build_deps autoconf automake pkgconf" ;;
        pacman) build_deps="$build_deps autoconf automake pkg-config" ;;
    esac

    if [ -n "$build_deps" ]; then
        # shellcheck disable=SC2086
        pkg_install $build_deps || {
            echo "  [WARN] Failed to install tmux build dependencies"
            PKG_ERRORS=$((PKG_ERRORS + 1))
            return 1
        }
    fi

    local build_dir
    build_dir="$(mktemp -d)"
    trap 'rm -rf "$build_dir"' RETURN

    # Clone tmux master
    if ! git clone --depth 1 https://github.com/tmux/tmux.git "$build_dir/tmux" 2>&1; then
        echo "  [WARN] Failed to clone tmux repo"
        PKG_ERRORS=$((PKG_ERRORS + 1))
        return 1
    fi

    cd "$build_dir/tmux"
    sh autogen.sh 2>&1 | tail -1
    ./configure --prefix="$HOME/.local" 2>&1 | tail -1
    make -j"$(nproc 2>/dev/null || echo 2)" 2>&1 | tail -1
    make install 2>&1 | tail -1
    cd - >/dev/null

    if [ -x "$HOME/.local/bin/tmux" ]; then
        echo "  [OK] tmux built and installed to ~/.local/bin/tmux"
        echo "  [OK] Version: $("$HOME/.local/bin/tmux" -V)"
    else
        echo "  [WARN] tmux build failed — binary not found"
        PKG_ERRORS=$((PKG_ERRORS + 1))
        return 1
    fi
}

# --- Install GitHub CLI ---
install_gh() {
    if [ "$DRY_RUN" = true ]; then
        if is_installed gh; then
            echo "  [DRY-RUN] Would update gh"
        else
            echo "  [DRY-RUN] Would install gh"
        fi
        return 0
    fi

    echo "  Installing/updating GitHub CLI..."
    case "${DOT_PKG_MGR:-}" in
        brew)
            brew install gh 2>&1 | tail -1
            ;;
        apt)
            # Always add GitHub's own repo for the latest version
            echo "  Adding GitHub CLI apt repository..."
            as_root mkdir -p /etc/apt/keyrings
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                | as_root tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                | as_root tee /etc/apt/sources.list.d/github-cli.list >/dev/null
            as_root apt-get update -qq 2>&1 | tail -1
            as_root apt-get install -y gh 2>&1 | tail -1
            ;;
        dnf)
            as_root dnf install -y 'dnf-command(config-manager)' 2>/dev/null || true
            as_root dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo 2>&1 | tail -1
            as_root dnf install -y gh 2>&1 | tail -1
            ;;
        yum)
            as_root yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null || true
            as_root yum install -y gh 2>&1 | tail -1
            ;;
        apk)
            as_root apk add --no-cache github-cli 2>&1 | tail -1
            ;;
        pacman)
            as_root pacman -S --noconfirm github-cli 2>&1 | tail -1
            ;;
        *)
            echo "  [WARN] Cannot install gh — unknown package manager"
            PKG_ERRORS=$((PKG_ERRORS + 1))
            return 1
            ;;
    esac

    if is_installed gh; then
        echo "  [OK] gh installed ($(gh --version | head -1))"
    else
        echo "  [WARN] gh install may have failed"
        PKG_ERRORS=$((PKG_ERRORS + 1))
    fi
}

# --- Install AWS CLI v2 ---
install_awscli() {
    if [ "$DRY_RUN" = true ]; then
        if is_installed aws; then
            echo "  [DRY-RUN] Would update AWS CLI"
        else
            echo "  [DRY-RUN] Would install AWS CLI"
        fi
        return 0
    fi

    if is_installed aws; then
        local current_ver
        current_ver="$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2)"
        echo "  [OK] AWS CLI already installed (v$current_ver), updating..."
    else
        echo "  Installing AWS CLI v2..."
    fi

    case "${DOT_OS:-}" in
        macos)
            if [ "${DOT_PKG_MGR:-}" = "brew" ]; then
                brew install awscli 2>&1 | tail -1
            fi
            ;;
        linux)
            # Alpine uses musl — the official AWS CLI v2 zip requires glibc
            if [ "${DOT_DISTRO:-}" = "alpine" ]; then
                echo "  Alpine detected — installing via pip..."
                if ! is_installed pip3 && ! is_installed pip; then
                    pkg_install python3 py3-pip 2>/dev/null || pkg_install python3-pip 2>/dev/null || true
                fi
                local pip_cmd="pip3"
                is_installed pip3 || pip_cmd="pip"
                if is_installed "$pip_cmd"; then
                    $pip_cmd install --break-system-packages --upgrade awscli 2>&1 | tail -1
                else
                    echo "  [WARN] pip not available — cannot install AWS CLI on Alpine"
                    PKG_ERRORS=$((PKG_ERRORS + 1))
                    return 1
                fi
            else
                local arch
                arch="$(uname -m)"
                case "$arch" in
                    x86_64) arch="x86_64" ;;
                    aarch64|arm64) arch="aarch64" ;;
                    *) echo "  [WARN] Unsupported architecture for AWS CLI: $arch"; return 1 ;;
                esac

                local tmpdir
                tmpdir="$(mktemp -d)"
                trap 'rm -rf "$tmpdir"' RETURN

                if curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip" -o "$tmpdir/awscliv2.zip" 2>&1; then
                    cd "$tmpdir"
                    unzip -q awscliv2.zip 2>&1 | tail -1

                    if is_installed aws; then
                        as_root ./aws/install --update --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin 2>&1 | tail -1
                    else
                        as_root ./aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin 2>&1 | tail -1
                    fi
                    cd - >/dev/null
                else
                    echo "  [WARN] Failed to download AWS CLI"
                    PKG_ERRORS=$((PKG_ERRORS + 1))
                    return 1
                fi
            fi
            ;;
    esac

    # Check both PATH and common install locations
    if is_installed aws; then
        echo "  [OK] AWS CLI installed ($(aws --version 2>&1 | awk '{print $1}'))"
    elif [ -x "$HOME/.local/bin/aws" ]; then
        echo "  [OK] AWS CLI installed ($("$HOME/.local/bin/aws" --version 2>&1 | awk '{print $1}'))"
    elif [ -x /usr/local/bin/aws ]; then
        echo "  [OK] AWS CLI installed ($(/usr/local/bin/aws --version 2>&1 | awk '{print $1}'))"
    else
        echo "  [WARN] AWS CLI install may have failed"
        PKG_ERRORS=$((PKG_ERRORS + 1))
    fi
}

# --- Install Claude Code ---
install_claude() {
    if [ "$NO_CLAUDE" = true ]; then
        echo "  [SKIP] Claude Code (--no-claude)"
        return 0
    fi

    if is_installed claude; then
        echo "  [OK] Claude Code already installed, updating..."
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] Would update Claude Code"
            return 0
        fi
        npm update -g @anthropic-ai/claude-code 2>&1 | tail -3
        return 0
    fi

    if ! is_installed node; then
        echo "  Installing Node.js..."
        case "${DOT_PKG_MGR:-}" in
            apt) pkg_install nodejs npm ;;
            dnf|yum) pkg_install nodejs npm ;;
            apk) pkg_install nodejs npm ;;
            pacman) pkg_install nodejs npm ;;
            brew) pkg_install node ;;
            *) echo "  [WARN] Cannot install Node.js — unknown package manager"; return 1 ;;
        esac
    fi

    if ! is_installed node; then
        echo "  [WARN] Node.js not available — cannot install Claude Code"
        PKG_ERRORS=$((PKG_ERRORS + 1))
        return 1
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would install Claude Code"
        return 0
    fi

    echo "  Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code@latest 2>&1 | tail -3
    if is_installed claude; then
        echo "  [OK] Claude Code installed"
    else
        echo "  [WARN] Claude Code install may have failed"
        PKG_ERRORS=$((PKG_ERRORS + 1))
    fi
}

# --- Main ---
install_packages() {
    echo "=== Package Installation ==="

    if [ "${DOT_HAS_SUDO:-false}" = false ] && [ "${DOT_IS_ROOT:-false}" = false ]; then
        echo "  [WARN] No sudo access and not root — skipping package installation"
        echo "  [INFO] Only user-level installs (tmux from source, Claude Code) will be attempted"
    fi

    # Update package index
    if [ "${DOT_HAS_SUDO:-false}" = true ] || [ "${DOT_IS_ROOT:-false}" = true ]; then
        pkg_update
    fi

    # Snap cleanup on Ubuntu
    snap_cleanup

    # Core packages
    local core_pkgs=()
    if ! is_installed git; then core_pkgs+=("git"); fi
    if ! is_installed vim; then core_pkgs+=("vim"); fi
    if ! is_installed curl; then core_pkgs+=("curl"); fi
    if ! is_installed wget; then core_pkgs+=("wget"); fi
    if ! is_installed jq; then core_pkgs+=("jq"); fi
    if ! is_installed rg; then core_pkgs+=("ripgrep"); fi
    if ! is_installed unzip; then core_pkgs+=("unzip"); fi

    # fd has different names
    if ! is_installed fd && ! is_installed fdfind; then
        core_pkgs+=("$(pkg_name fd)")
    fi

    if [ ${#core_pkgs[@]} -gt 0 ]; then
        if [ "${DOT_HAS_SUDO:-false}" = true ] || [ "${DOT_IS_ROOT:-false}" = true ]; then
            pkg_install "${core_pkgs[@]}" || PKG_ERRORS=$((PKG_ERRORS + 1))
        else
            echo "  [SKIP] Core packages (no sudo): ${core_pkgs[*]}"
        fi
    else
        echo "  [OK] Core packages already installed"
    fi

    # eza — optional, only if in repos
    if ! is_installed eza; then
        case "${DOT_PKG_MGR:-}" in
            apt|brew|pacman|apk)
                if [ "${DOT_HAS_SUDO:-false}" = true ] || [ "${DOT_IS_ROOT:-false}" = true ]; then
                    pkg_install eza 2>/dev/null || echo "  [INFO] eza not available in repos — using plain ls"
                fi
                ;;
            *)
                echo "  [INFO] eza not available for ${DOT_PKG_MGR:-unknown} — using plain ls"
                ;;
        esac
    fi

    # GitHub CLI
    install_gh

    # AWS CLI
    install_awscli

    # tmux — always build from nightly
    build_tmux || echo "  [WARN] tmux nightly build failed — using system tmux if available"

    # Claude Code
    install_claude

    echo ""
    if [ "$PKG_ERRORS" -gt 0 ]; then
        echo "  [WARN] $PKG_ERRORS package error(s) encountered"
        return 1
    fi
    return 0
}

install_packages
