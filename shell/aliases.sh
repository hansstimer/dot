# aliases.sh — POSIX aliases shared by bash and zsh
# This file is sourced, not executed

# === Navigation ===
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# === Listing ===
if command -v eza >/dev/null 2>&1; then
    alias ls='eza'
    alias ll='eza -lah'
    alias la='eza -a'
    alias l='eza -l'
elif [ "$(uname -s)" = "Darwin" ]; then
    alias ls='ls -G'
    alias ll='ls -lAhG'
    alias la='ls -AG'
    alias l='ls -lG'
else
    alias ls='ls --color=auto'
    alias ll='ls -lAh --color=auto'
    alias la='ls -A --color=auto'
    alias l='ls -l --color=auto'
fi

# === Git ===
alias gs='git status -sb'
alias gd='git diff'
alias gdc='git diff --cached'
alias gl='git log --oneline -20'
alias glg='git log --oneline --graph --all -20'
alias gco='git checkout'
alias gcm='git commit -m'
alias gp='git push'
alias ga='git add'
alias gpl='git pull'

# === Tmux ===
alias ta='tmux attach -t main 2>/dev/null || tmux new-session -s main'
alias tl='tmux list-sessions'
alias tk='tmux kill-session -t'

# === Claude Code ===
alias cc='claude'
alias ccc='claude --continue'

# === Grep ===
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# === Safety ===
alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

# === Platform-specific clipboard ===
if [ "$(uname -s)" != "Darwin" ]; then
    if command -v xclip >/dev/null 2>&1; then
        alias pbcopy='xclip -selection clipboard'
        alias pbpaste='xclip -selection clipboard -o'
    elif command -v xsel >/dev/null 2>&1; then
        alias pbcopy='xsel --clipboard --input'
        alias pbpaste='xsel --clipboard --output'
    fi
fi

# === fd normalization (Debian/Ubuntu) ===
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    alias fd='fdfind'
fi
