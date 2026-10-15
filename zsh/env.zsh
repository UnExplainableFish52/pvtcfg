# loki environment (minimal)

export EDITOR='nano'
export VISUAL='nano'

typeset -U path PATH
path_add() { [[ -d "$1" ]] && path=("$1" $path); }
path_add "${ZSHCFG_HOME:-$HOME}/bin"
path_add "${ZSHCFG_HOME:-$HOME}/.local/bin"
