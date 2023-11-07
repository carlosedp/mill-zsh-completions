0="${${0:#$ZSH_ARGZERO}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

fpath=("${0:h}/completions" $fpath)

# Load mill functions for update and prompt
source "${0:A:h}/mill-functions.zsh"
