#! /usr/bin/env nix-shell
#! nix-shell -i python -p python3

from sys import argv

# This is an example file. Replace the usernames with the ones created and replace the UDIDs with the ones gotten according to `README.md`.
someUser="userNameHere_iosbackup"
someUser2="user2NameHere_iosbackup"
lookupTable={
    "00008020-008D4548007B4F26": someUser,
    "00008020-008D4548007B4F27": someUser,
    "00008020-008D4548007B4F28": someUser2,
}

if __name__ == '__main__':
    print(lookupTable[argv[1]])
