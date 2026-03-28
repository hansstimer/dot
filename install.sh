#!/usr/bin/env bash
# install.sh — Single-command bootstrap entry point for dot
set -euo pipefail

# --- Resolve DOT_DIR ---
DOT_DIR="$(cd "$(dirname "$0")" && pwd)"
export DOT_DIR

# --- Parse arguments ---
DOT_REMOTE=false
DOT_MINIMAL=false
DOT_DRY_RUN=false
DOT_NO_CLAUDE=false

for arg in "$@"; do
    case "$arg" in
        --remote) DOT_REMOTE=true ;;
        --minimal) DOT_MINIMAL=true ;;
        --dry-run) DOT_DRY_RUN=true ;;
        --no-claude) DOT_NO_CLAUDE=true ;;
        --help|-h)
            echo "Usage: install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --remote     Remote host mode (skip macOS-only configs, strip git SSH rewrite)"
            echo "  --minimal    Configs + terminfo only, no package installation"
            echo "  --no-claude  Skip Claude Code installation"
            echo "  --dry-run    Show what would happen without making changes"
            echo "  --help       Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

export DOT_REMOTE DOT_MINIMAL DOT_DRY_RUN DOT_NO_CLAUDE

# --- macOS bash version check ---
# macOS ships bash 3.2 which is too old. Re-exec under zsh if needed.
if [ "$(uname -s)" = "Darwin" ]; then
    bash_major="${BASH_VERSINFO[0]:-0}"
    if [ "$bash_major" -lt 4 ] && command -v zsh >/dev/null 2>&1; then
        exec zsh "$0" "$@"
    fi
fi

echo "╔══════════════════════════════════════╗"
echo "║       dot — dotfiles bootstrap       ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "DOT_DIR: $DOT_DIR"
echo "Mode: ${DOT_REMOTE:+remote }${DOT_MINIMAL:+minimal }${DOT_DRY_RUN:+dry-run }${DOT_NO_CLAUDE:+no-claude}"
echo ""

# Track phase results
PHASE_ERRORS=0

# --- Helper: run a phase ---
run_phase() {
    local name="$1"
    local script="$2"
    local required="${3:-false}"

    if [ ! -f "$script" ]; then
        echo "[ERROR] Phase script not found: $script"
        if [ "$required" = true ]; then
            exit 1
        fi
        PHASE_ERRORS=$((PHASE_ERRORS + 1))
        return
    fi

    if (source "$script"); then
        return 0
    else
        local rc=$?
        echo ""
        echo "[WARN] Phase '$name' had errors (exit code: $rc)"
        if [ "$required" = true ]; then
            echo "[FATAL] Required phase '$name' failed — aborting"
            exit 1
        fi
        PHASE_ERRORS=$((PHASE_ERRORS + 1))
        return 0  # Continue to next phase
    fi
}

# --- Phase 1: Detection (fatal, sourced directly so vars propagate) ---
source "$DOT_DIR/setup/detect.sh" || { echo "[FATAL] Detection failed"; exit 1; }

# --- Phase 2: Packages (skip if --minimal) ---
if [ "$DOT_MINIMAL" = true ]; then
    echo "=== Package Installation ==="
    echo "  [SKIP] Minimal mode — no package installation"
    echo ""
else
    run_phase "packages" "$DOT_DIR/setup/packages.sh"
fi

# --- Phase 3: Terminfo ---
run_phase "terminfo" "$DOT_DIR/setup/terminfo.sh"

# --- Phase 4: Linking ---
run_phase "link" "$DOT_DIR/setup/link.sh"

# --- Phase 5: Post-install ---
run_phase "post-install" "$DOT_DIR/setup/post-install.sh"

# --- Summary ---
echo "╔══════════════════════════════════════╗"
if [ "$PHASE_ERRORS" -eq 0 ]; then
    echo "║         Install complete! ✓          ║"
else
    echo "║    Install complete (with warns)     ║"
fi
echo "╚══════════════════════════════════════╝"
echo ""

if [ "$DOT_DRY_RUN" = true ]; then
    echo "This was a dry run — no changes were made."
fi

echo "Restart your shell or run: source ~/.bashrc  (or ~/.zshrc)"
echo ""

exit "$( [ "$PHASE_ERRORS" -eq 0 ] && echo 0 || echo 1 )"
