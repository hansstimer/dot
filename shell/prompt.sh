# prompt.sh — Built-in prompt, no external dependencies
# Works in both bash and zsh. Sourced, not executed.

# Git branch from .git/HEAD — no subprocess
_dot_git_branch() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/.git/HEAD" ]; then
            local head
            head="$(cat "$dir/.git/HEAD" 2>/dev/null)" || return
            case "$head" in
                ref:\ refs/heads/*)
                    printf '%s' "${head#ref: refs/heads/}"
                    ;;
                *)
                    # Detached HEAD — show short SHA
                    printf '%s' "${head:0:8}"
                    ;;
            esac
            return
        fi
        dir="${dir%/*}"
        [ -z "$dir" ] && dir="/"
    done
}

# Build the prompt
_dot_setup_prompt() {
    # Colors (works in both bash and zsh)
    local reset green cyan magenta red yellow

    if [ -n "${ZSH_VERSION:-}" ]; then
        reset="%f%b"
        green="%F{green}%B"
        cyan="%F{cyan}%B"
        magenta="%F{magenta}"
        red="%F{red}%B"
        yellow="%F{yellow}"
    else
        reset='\[\033[0m\]'
        green='\[\033[1;32m\]'
        cyan='\[\033[1;36m\]'
        magenta='\[\033[0;35m\]'
        red='\[\033[1;31m\]'
        yellow='\[\033[0;33m\]'
    fi

    # SSH badge
    local ssh_badge=""
    if [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ] || [ -n "${SSH_CONNECTION:-}" ]; then
        ssh_badge="${red}[SSH] ${reset}"
    fi

    if [ -n "${ZSH_VERSION:-}" ]; then
        # Zsh prompt
        setopt PROMPT_SUBST

        # Use precmd to update git branch
        _dot_precmd() {
            local branch
            branch="$(_dot_git_branch)"
            if [ -n "$branch" ]; then
                _DOT_GIT_INFO=" %F{magenta}${branch}%f"
            else
                _DOT_GIT_INFO=""
            fi
        }

        # Add to precmd hooks
        autoload -Uz add-zsh-hook
        add-zsh-hook precmd _dot_precmd

        PROMPT="${ssh_badge}${green}%n@%m${reset} ${cyan}%3~${reset}\${_DOT_GIT_INFO}
${yellow}❯${reset} "
    else
        # Bash prompt — use PROMPT_COMMAND to update git info
        _dot_prompt_command() {
            local branch
            branch="$(_dot_git_branch)"
            if [ -n "$branch" ]; then
                _DOT_GIT_INFO=" \033[0;35m${branch}\033[0m"
            else
                _DOT_GIT_INFO=""
            fi
        }

        # Append to PROMPT_COMMAND
        if [ -z "${PROMPT_COMMAND:-}" ]; then
            PROMPT_COMMAND="_dot_prompt_command"
        else
            PROMPT_COMMAND="_dot_prompt_command;${PROMPT_COMMAND}"
        fi

        # \w gives full path; use bash parameter expansion for abbreviated path
        PS1="${ssh_badge}${green}\u@\h${reset} ${cyan}\w${reset}\${_DOT_GIT_INFO}\n${yellow}❯${reset} "
    fi
}

_dot_setup_prompt
