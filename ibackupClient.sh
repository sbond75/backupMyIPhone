# Grab config
source "$scriptDir/config.sh"

dest="$config__clientDirectory/$username"

logfile="$dest/logs/$(date '+%Y-%m-%d %I-%M-%S %p').log.txt"
