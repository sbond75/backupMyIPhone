# https://stackoverflow.com/questions/39239379/add-timestamp-to-teed-output-but-not-original-output
# Usage: `echo "test" | tee_with_timestamps "file.txt"`
function tee_with_timestamps () {
    local logfile=$1
    while read data; do
	echo "${data}" | sed -e "s/^/$(date '+%F %T') /" >> "${logfile}"
	echo "${data}"
    done
}
