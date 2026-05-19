# Completion — cache the dump under XDG cache (keeps $HOME clean) and only
# do the slow fpath security audit at most once a day; otherwise use -C.
autoload -Uz compinit
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
[[ -d ${_zcompdump:h} ]] || mkdir -p "${_zcompdump:h}"
if [[ -n ${_zcompdump}(#qN.mh+24) ]]; then
    compinit -d "$_zcompdump"
else
    compinit -C -d "$_zcompdump"
fi
unset _zcompdump

zstyle ':completion:*' menu select
zstyle ':completion:*' rehash true
