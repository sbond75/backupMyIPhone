scriptDir="$(dirname "${BASH_SOURCE[0]}")"
# https://unix.stackexchange.com/questions/609739/bash-exported-function-not-visible-but-variables-are : "The solution" : "Don't use exported functions. They have little use in the first place, and for you they are completely useless."
source "$scriptDir/teeWithTimestamps.sh" # load in the function directly (instead of using `export -f` outside this script) so it actually works

export -f tee_with_timestamps
typeset -fx tee_with_timestamps

bash "$@"
