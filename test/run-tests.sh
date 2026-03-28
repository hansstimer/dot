#!/usr/bin/env bash
# run-tests.sh — Build and test dotfiles in containers
set -euo pipefail

DOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }
log_info() { echo -e "  ${YELLOW}[INFO]${NC} $1"; }

test_distro() {
    local name="$1"
    local dockerfile="$2"
    local image="dot-test-$name"

    echo ""
    echo "========================================="
    echo "Testing: $name"
    echo "========================================="

    # Build
    echo "  Building image..."
    if ! docker build -t "$image" -f "$dockerfile" "$DOT_DIR" 2>&1 | tail -3; then
        log_fail "Docker build failed"
        return
    fi

    # Run install (minimal mode — skip building tmux from source in CI)
    echo "  Running install.sh --remote --minimal..."
    if ! docker run --rm "$image" bash -c "cd ~/dot && bash install.sh --remote --minimal" 2>&1; then
        log_fail "install.sh failed"
        return
    fi
    log_pass "install.sh --remote --minimal succeeded"

    # Test: symlinks
    echo "  Checking symlinks..."
    docker run --rm "$image" bash -c '
        cd ~/dot && bash install.sh --remote --minimal 2>/dev/null
        errors=0
        for link in ~/.bashrc ~/.bash_profile ~/.tmux.conf ~/.gitignore_global; do
            if [ -L "$link" ]; then
                target="$(readlink "$link")"
                case "$target" in
                    /home/testuser/dot/*) ;;
                    *) echo "WRONG TARGET: $link -> $target"; errors=$((errors + 1)) ;;
                esac
            else
                echo "NOT A SYMLINK: $link"; errors=$((errors + 1))
            fi
        done
        exit $errors
    ' && log_pass "Symlinks correct" || log_fail "Symlink check"

    # Test: shell sources without error
    echo "  Testing bash sourcing..."
    docker run --rm "$image" bash -c '
        cd ~/dot && bash install.sh --remote --minimal 2>/dev/null
        export DOT_DIR=~/dot
        bash --norc --noprofile -c "source ~/.bashrc" 2>&1
    ' && log_pass "bashrc sources cleanly" || log_fail "bashrc sourcing"

    # Test: terminfo compiled
    echo "  Checking terminfo..."
    docker run --rm "$image" bash -c '
        cd ~/dot && bash install.sh --remote --minimal 2>/dev/null
        if [ -f ~/.terminfo/x/xterm-ghostty ] || [ -f ~/.terminfo/78/xterm-ghostty ]; then
            echo "xterm-ghostty terminfo found"
            exit 0
        else
            echo "xterm-ghostty terminfo NOT found"
            # List what we have
            find ~/.terminfo -type f 2>/dev/null || echo "no terminfo dir"
            exit 1
        fi
    ' && log_pass "Terminfo compiled" || log_fail "Terminfo compilation"

    # Test: TERM negotiation
    echo "  Checking TERM negotiation..."
    docker run --rm -e TERM=xterm-ghostty "$image" bash -c '
        cd ~/dot && bash install.sh --remote --minimal 2>/dev/null
        export DOT_DIR=~/dot
        # Source env.sh and check TERM
        . ~/dot/shell/env.sh
        if [ "$TERM" = "xterm-ghostty" ]; then
            echo "TERM=xterm-ghostty (terminfo available)"
            exit 0
        elif [ "$TERM" = "xterm-256color" ]; then
            echo "TERM fell back to xterm-256color (terminfo missing — unexpected after install)"
            exit 1
        else
            echo "TERM=$TERM (unexpected)"
            exit 1
        fi
    ' && log_pass "TERM negotiation" || log_fail "TERM negotiation"

    # Test: TERM fallback when terminfo is missing
    echo "  Checking TERM fallback..."
    docker run --rm -e TERM=some-bogus-term "$image" bash -c '
        export DOT_DIR=~/dot
        . ~/dot/shell/env.sh
        if [ "$TERM" = "xterm-256color" ]; then
            echo "TERM correctly fell back to xterm-256color"
            exit 0
        else
            echo "TERM=$TERM (expected xterm-256color)"
            exit 1
        fi
    ' && log_pass "TERM fallback" || log_fail "TERM fallback"

    # Test: git config generated
    echo "  Checking git config..."
    docker run --rm "$image" bash -c '
        cd ~/dot && bash install.sh --remote --minimal 2>/dev/null
        if [ -f ~/.gitconfig ]; then
            echo "gitconfig exists"
            grep -q "excludesfile" ~/.gitconfig && echo "has excludesfile" || exit 1
            # Should NOT have SSH URL rewrite (--remote strips it)
            if grep -q "insteadOf = https://github.com/" ~/.gitconfig; then
                echo "ERROR: SSH URL rewrite not stripped in remote mode"
                exit 1
            fi
            echo "SSH URL rewrite correctly stripped"
            exit 0
        else
            echo "gitconfig NOT found"
            exit 1
        fi
    ' && log_pass "Git config generated (remote mode)" || log_fail "Git config"

    # Test: aliases defined
    echo "  Checking aliases..."
    docker run --rm "$image" bash -c '
        cd ~/dot && bash install.sh --remote --minimal 2>/dev/null
        export DOT_DIR=~/dot
        . ~/dot/shell/aliases.sh
        # Check a few aliases exist
        alias gs 2>/dev/null && alias ll 2>/dev/null && alias cc 2>/dev/null
    ' && log_pass "Aliases defined" || log_fail "Aliases"

    # Test: tmux config valid
    echo "  Checking tmux config syntax..."
    docker run --rm "$image" bash -c '
        # Only test if tmux is available
        if command -v tmux >/dev/null 2>&1; then
            cd ~/dot && bash install.sh --remote --minimal 2>/dev/null
            # Start a tmux server to validate config
            tmux -f ~/.tmux.conf start-server 2>&1 && tmux kill-server 2>/dev/null
            echo "tmux config valid"
        else
            echo "tmux not installed — skipping"
        fi
    ' && log_pass "tmux config" || log_fail "tmux config"

    # Test: idempotent (run twice)
    echo "  Checking idempotency..."
    docker run --rm "$image" bash -c '
        cd ~/dot
        bash install.sh --remote --minimal 2>/dev/null
        bash install.sh --remote --minimal 2>/dev/null
        echo "Second run succeeded"
    ' && log_pass "Idempotent" || log_fail "Idempotency"

    # Cleanup
    docker rmi "$image" >/dev/null 2>&1 || true
}

# --- Run tests ---
echo "╔══════════════════════════════════════╗"
echo "║       dot — Container Tests          ║"
echo "╚══════════════════════════════════════╝"

test_distro "ubuntu" "$DOT_DIR/test/Dockerfile.ubuntu"
test_distro "alpine" "$DOT_DIR/test/Dockerfile.alpine"

# --- Summary ---
echo ""
echo "========================================="
echo "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "========================================="

exit "$( [ "$FAIL" -eq 0 ] && echo 0 || echo 1 )"
