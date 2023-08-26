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

def removeDashes_(s):
    return s.replace('-', '')

if __name__ == '__main__':
    toGet = argv[1]
    removeDashes = (argv[2] == '1') if len(argv) > 2 else False
    printTableKeys = (argv[3] == '1') if len(argv) > 3 else False
    if removeDashes:
        toGet = removeDashes_(toGet)
        lookupTable = {removeDashes_(k): v for k,v in lookupTable.items()}

    if printTableKeys:
        for k in lookupTable.keys():
            print(k)
    else:
        print(lookupTable[toGet])
