#!/usr/bin/env bash
# detect.sh — OS/shell/tool detection helpers
# Sourced by install.sh. Sets global variables for other phases.
set -euo pipefail

# --- OS Detection ---
detect_os() {
    DOT_OS="unknown"
    DOT_DISTRO="unknown"
    DOT_PKG_MGR="unknown"

    case "$(uname -s)" in
        Darwin)
            DOT_OS="macos"
            DOT_DISTRO="macos"
            DOT_PKG_MGR="brew"
            ;;
        Linux)
            DOT_OS="linux"
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                case "$ID" in
                    ubuntu|debian|pop|linuxmint)
                        DOT_DISTRO="$ID"
                        DOT_PKG_MGR="apt"
                        ;;
                    fedora)
                        DOT_DISTRO="fedora"
                        DOT_PKG_MGR="dnf"
                        ;;
                    rhel|centos|rocky|alma|ol)
                        DOT_DISTRO="$ID"
                        if command -v dnf >/dev/null 2>&1; then
                            DOT_PKG_MGR="dnf"
                        else
                            DOT_PKG_MGR="yum"
                        fi
                        ;;
                    amzn)
                        DOT_DISTRO="amzn"
                        if command -v dnf >/dev/null 2>&1; then
                            DOT_PKG_MGR="dnf"
                        else
                            DOT_PKG_MGR="yum"
                        fi
                        ;;
                    alpine)
                        DOT_DISTRO="alpine"
                        DOT_PKG_MGR="apk"
                        ;;
                    arch|manjaro|endeavouros)
                        DOT_DISTRO="$ID"
                        DOT_PKG_MGR="pacman"
                        ;;
                    *)
                        DOT_DISTRO="$ID"
                        # Try to detect package manager
                        if command -v apt-get >/dev/null 2>&1; then
                            DOT_PKG_MGR="apt"
                        elif command -v dnf >/dev/null 2>&1; then
                            DOT_PKG_MGR="dnf"
                        elif command -v yum >/dev/null 2>&1; then
                            DOT_PKG_MGR="yum"
                        elif command -v apk >/dev/null 2>&1; then
                            DOT_PKG_MGR="apk"
                        elif command -v pacman >/dev/null 2>&1; then
                            DOT_PKG_MGR="pacman"
                        fi
                        ;;
                esac
            elif [ -f /etc/alpine-release ]; then
                DOT_DISTRO="alpine"
                DOT_PKG_MGR="apk"
            fi
            ;;
    esac

    export DOT_OS DOT_DISTRO DOT_PKG_MGR
}

# --- Shell Detection ---
detect_shell() {
    DOT_HAS_ZSH=false
    DOT_HAS_BASH=false
    DOT_CURRENT_SHELL="$(basename "${SHELL:-/bin/sh}")"

    if command -v zsh >/dev/null 2>&1; then
        DOT_HAS_ZSH=true
    fi
    if command -v bash >/dev/null 2>&1; then
        DOT_HAS_BASH=true
    fi

    export DOT_HAS_ZSH DOT_HAS_BASH DOT_CURRENT_SHELL
}

# --- SSH Detection ---
detect_ssh() {
    DOT_IS_SSH=false
    if [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ] || [ -n "${SSH_CONNECTION:-}" ]; then
        DOT_IS_SSH=true
    fi
    export DOT_IS_SSH
}

# --- Sudo Detection ---
detect_sudo() {
    DOT_HAS_SUDO=false
    DOT_IS_ROOT=false

    if [ "$(id -u)" -eq 0 ]; then
        DOT_IS_ROOT=true
        DOT_HAS_SUDO=true  # root doesn't need sudo
    elif command -v sudo >/dev/null 2>&1; then
        # Check if sudo works without a password
        if sudo -n true 2>/dev/null; then
            DOT_HAS_SUDO=true
        fi
    fi

    export DOT_HAS_SUDO DOT_IS_ROOT
}

# --- Tool Detection ---
detect_tools() {
    DOT_HAS_GIT=false
    DOT_HAS_TMUX=false
    DOT_HAS_CURL=false
    DOT_HAS_NODE=false
    DOT_HAS_CLAUDE=false
    DOT_HAS_TIC=false

    command -v git >/dev/null 2>&1 && DOT_HAS_GIT=true
    command -v tmux >/dev/null 2>&1 && DOT_HAS_TMUX=true
    command -v curl >/dev/null 2>&1 && DOT_HAS_CURL=true
    command -v node >/dev/null 2>&1 && DOT_HAS_NODE=true
    command -v claude >/dev/null 2>&1 && DOT_HAS_CLAUDE=true
    command -v tic >/dev/null 2>&1 && DOT_HAS_TIC=true

    # tmux version check
    DOT_TMUX_VERSION=""
    if [ "$DOT_HAS_TMUX" = true ]; then
        DOT_TMUX_VERSION="$(tmux -V 2>/dev/null | sed 's/[^0-9.]//g' || echo "")"
    fi

    export DOT_HAS_GIT DOT_HAS_TMUX DOT_HAS_CURL DOT_HAS_NODE DOT_HAS_CLAUDE DOT_HAS_TIC DOT_TMUX_VERSION
}

# --- Interactive Detection ---
detect_interactive() {
    DOT_IS_INTERACTIVE=false
    if [ -t 0 ] && [ -t 1 ]; then
        DOT_IS_INTERACTIVE=true
    fi
    export DOT_IS_INTERACTIVE
}

# --- Run All Detection ---
detect_all() {
    detect_os
    detect_shell
    detect_ssh
    detect_sudo
    detect_tools
    detect_interactive

    echo "=== Environment Detection ==="
    echo "  OS:           $DOT_OS ($DOT_DISTRO)"
    echo "  Package mgr:  $DOT_PKG_MGR"
    echo "  Shell:        $DOT_CURRENT_SHELL (bash=$DOT_HAS_BASH, zsh=$DOT_HAS_ZSH)"
    echo "  SSH session:  $DOT_IS_SSH"
    echo "  Sudo:         $DOT_HAS_SUDO (root=$DOT_IS_ROOT)"
    echo "  Git:          $DOT_HAS_GIT"
    echo "  tmux:         $DOT_HAS_TMUX${DOT_TMUX_VERSION:+ (v$DOT_TMUX_VERSION)}"
    echo "  tic:          $DOT_HAS_TIC"
    echo "  Node:         $DOT_HAS_NODE"
    echo "  Claude:       $DOT_HAS_CLAUDE"
    echo "  Interactive:  $DOT_IS_INTERACTIVE"
    echo ""
}

detect_all
