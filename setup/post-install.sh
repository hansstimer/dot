#!/usr/bin/env bash
# post-install.sh — Final setup steps
set -euo pipefail

DOT_DIR="${DOT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
DRY_RUN="${DOT_DRY_RUN:-false}"

echo "=== Post-Install ==="

# Add ~/dot/bin to PATH check
if [ -d "$DOT_DIR/bin" ]; then
    case ":$PATH:" in
        *":$DOT_DIR/bin:"*) ;;
        *)
            echo "  [INFO] $DOT_DIR/bin will be on PATH after shell restart"
            ;;
    esac
fi

# Ensure ~/.local/bin is on PATH (for tmux built from source)
if [ -d "$HOME/.local/bin" ]; then
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *)
            export PATH="$HOME/.local/bin:$PATH"
            echo "  [INFO] Added ~/.local/bin to PATH"
            ;;
    esac
fi

# Write version file
if [ "$DRY_RUN" != true ]; then
    version_info="installed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ -d "$DOT_DIR/.git" ]; then
        sha="$(cd "$DOT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
        version_info="$version_info\ngit: $sha"
    fi
    printf "%b\n" "$version_info" > "$DOT_DIR/.version"
    echo "  [OK] Wrote $DOT_DIR/.version"
fi

# Color validation test
echo ""
echo "  === Color Test ==="
echo "  256-color test:"
printf "  "
for i in $(seq 0 7); do
    printf "\033[48;5;%dm  \033[0m" "$i"
done
printf "\n  "
for i in $(seq 8 15); do
    printf "\033[48;5;%dm  \033[0m" "$i"
done
printf "\n"

echo "  True color (24-bit) test:"
printf "  "
for i in $(seq 0 6 255); do
    printf "\033[48;2;%d;0;0m \033[0m" "$i"
done
printf "\n  "
for i in $(seq 0 6 255); do
    printf "\033[48;2;0;%d;0m \033[0m" "$i"
done
printf "\n  "
for i in $(seq 0 6 255); do
    printf "\033[48;2;0;0;%dm \033[0m" "$i"
done
printf "\n"

echo "  Text style test:"
printf "  \033[1mBold\033[0m  \033[3mItalic\033[0m  \033[4mUnderline\033[0m  \033[1;3;4mAll three\033[0m\n"

echo ""
echo "  TERM=$TERM"
echo "  COLORTERM=${COLORTERM:-unset}"
echo ""
