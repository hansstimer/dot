# env.sh — POSIX env vars shared by bash and zsh
# This file is sourced, not executed — no shebang, no set -e

# === TERM negotiation (MUST be first) ===
# Prevent terminfo warnings when TERM is set to something the host doesn't know
_dot_has_terminfo() {
    # Check if terminfo entry exists for given TERM
    local term="$1"
    # Try infocmp first (most reliable)
    if command -v infocmp >/dev/null 2>&1; then
        infocmp "$term" >/dev/null 2>&1 && return 0
    fi
    # Fallback: check filesystem
    local first_char="${term%"${term#?}"}"
    local hex
    hex=$(printf '%02x' "'$first_char" 2>/dev/null || echo "")
    for dir in "$HOME/.terminfo" "/usr/share/terminfo" "/usr/lib/terminfo" "/etc/terminfo"; do
        [ -f "$dir/$first_char/$term" ] && return 0
        [ -n "$hex" ] && [ -f "$dir/$hex/$term" ] && return 0
    done
    return 1
}

# Inside tmux: trust tmux's TERM, don't override
if [ -z "${TMUX:-}" ]; then
    # Not in tmux — validate TERM
    if [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ]; then
        if ! _dot_has_terminfo "$TERM"; then
            export TERM="xterm-256color"
        fi
    elif [ -z "${TERM:-}" ]; then
        export TERM="xterm-256color"
    fi
fi

# Always export truecolor
export COLORTERM=truecolor

# === Editor ===
export EDITOR=vim
export VISUAL=vim
export PAGER="less -FRX"

# === PATH construction ===
# Deduplicated, order-preserving path prepend
_dot_prepend_path() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) [ -d "$1" ] && export PATH="$1:$PATH" ;;
    esac
}

# Homebrew (macOS)
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

_dot_prepend_path "$HOME/.local/bin"
_dot_prepend_path "$HOME/go/bin"
_dot_prepend_path "$HOME/.npm-global/bin"

# dot/bin
DOT_DIR="${DOT_DIR:-$HOME/dot}"
[ -d "$DOT_DIR/bin" ] && _dot_prepend_path "$DOT_DIR/bin"

unset -f _dot_prepend_path
