# Shell options
setopt RM_STAR_WAIT              # Prompts for confirmation after 'rm *' etc
setopt NO_CLOBBER                # Don't overwrite files with >; use >| to force
setopt NOCORRECTALL              # Disable argument correction
setopt CORRECT                   # Enable command correction

# History
setopt BANG_HIST                 # Treat '!' specially during expansion
setopt EXTENDED_HISTORY          # Write ':start:elapsed;command' format
setopt SHARE_HISTORY             # Share history between all sessions
setopt HIST_EXPIRE_DUPS_FIRST   # Expire duplicates first when trimming
setopt HIST_IGNORE_DUPS          # Don't record duplicate of previous event
setopt HIST_IGNORE_ALL_DUPS     # Delete old duplicate when new one is added
setopt HIST_FIND_NO_DUPS        # Don't display previously found duplicates
setopt HIST_IGNORE_SPACE        # Don't record events starting with a space
setopt HIST_SAVE_NO_DUPS        # Don't write duplicates to history file
setopt HIST_VERIFY               # Don't execute immediately on history expansion
setopt HIST_BEEP                 # Beep on non-existent history

HISTFILE="${HOME}/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
