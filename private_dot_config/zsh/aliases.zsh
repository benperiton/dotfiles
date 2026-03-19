# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# Changing "ls" to "lsd"
alias ls='lsd -al --color=always --group-directories-first'
alias la='lsd -a --color=always --group-directories-first'
alias ll='lsd -l --color=always --group-directories-first'
alias lt='lsd -aT --color=always --group-directories-first'
alias l.='lsd -a | grep "^\."'
alias sl='ls'

# Adding flags
alias df='df -h'
alias free='free -h'

# Play safe
alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

# Convenience
alias mkdir='mkdir -p'

# Replacements
alias top='htop'
alias cat='bat --style=plain'
alias grep='rg'
alias ping='prettyping --nolegend'
alias help='tldr'
alias open='mimeo'

# Development
alias lg='lazygit'
alias vim='nvim'

# Git
alias ga='git add'
alias gaa='git add --all'
alias gcmsg='git commit -m'
alias gd='git diff'
alias gst='git status'
alias gp='git push'
alias gl='git log --graph --abbrev-commit --pretty=oneline --decorate'

# Misc
alias fuck='sudo $(fc -ln -1)'
alias tb='nc termbin.com 9999'
