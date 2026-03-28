#!/usr/bin/env bash
# terminfo.sh — Compile and install ghostty terminfo
set -euo pipefail

DOT_DIR="${DOT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
DRY_RUN="${DOT_DRY_RUN:-false}"

terminfo_src="$DOT_DIR/terminfo/xterm-ghostty.terminfo"

if [ ! -f "$terminfo_src" ]; then
    echo "  [WARN] Terminfo source not found: $terminfo_src"
    exit 0
fi

# Check if already compiled
check_terminfo_exists() {
    # Try common locations
    for dir in "$HOME/.terminfo" "/usr/share/terminfo" "/usr/lib/terminfo" "/etc/terminfo"; do
        # terminfo is stored in subdirectories by first char (or hex)
        if [ -f "$dir/x/xterm-ghostty" ] || [ -f "$dir/78/xterm-ghostty" ]; then
            return 0
        fi
    done
    return 1
}

if check_terminfo_exists; then
    echo "  [OK] xterm-ghostty terminfo already installed"
    exit 0
fi

if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] Would compile xterm-ghostty terminfo"
    exit 0
fi

if ! command -v tic >/dev/null 2>&1; then
    echo "  [WARN] tic not found — cannot compile terminfo. TERM will fall back to xterm-256color."
    exit 0
fi

echo "  Compiling xterm-ghostty terminfo..."
mkdir -p "$HOME/.terminfo"

# Try with -x for extended capabilities first, fall back without
if tic -x -o "$HOME/.terminfo" "$terminfo_src" 2>/dev/null; then
    echo "  [OK] Compiled with extended capabilities"
elif tic -o "$HOME/.terminfo" "$terminfo_src" 2>/dev/null; then
    echo "  [OK] Compiled (without extended capabilities)"
else
    echo "  [WARN] Failed to compile terminfo"
    exit 1
fi

# Verify
if check_terminfo_exists; then
    echo "  [OK] Verified: xterm-ghostty terminfo is available"
else
    echo "  [WARN] Compilation succeeded but terminfo not found at expected path"
fi
