# loki options (history)

# Allow named-directory navigation without a tilde: cd shell_config.
setopt CDABLE_VARS

HISTFILE="${ZSHCFG_HOME:-$HOME}/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000

setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY

