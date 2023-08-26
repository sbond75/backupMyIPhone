# Get all configured users into `vars`
prefix=config__
suffix=_ftp
# https://unix.stackexchange.com/questions/245989/list-variables-with-prefix-where-the-prefix-is-stored-in-another-variable
eval 'vars=(${!'"$prefix"'@})' # Filter {all bash variables defined currently} by prefix first
# Now filter by suffix, saving the final result into `users` array
users=()
usersVars=()
for i in "${vars[@]}"
do
    if [[ $i == *$suffix ]]; then
	#echo "String ends with given suffix."
	usersVars+=("$i") # Add the user with prefix "config__" and suffix "_ftp" there still
	# Now remove the suffix and prefix:
	local foo=${i#"$prefix"}
	foo=${i%"$suffix"}
	users+=("$foo")
    else
	#echo "String does not end with given suffix."
	:
    fi
done
