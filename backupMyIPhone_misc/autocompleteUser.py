from sys import path
import os
scriptDir=os.path.dirname(os.path.realpath(__file__))
#path.append(os.path.join(os.path.dirname(scriptDir), 'backupMyIPhone'))
path.append(os.path.dirname(scriptDir))
import udidToFolderLookupTable as u
from sys import argv

queryUser = argv[1]

users = {x for x in u.lookupTable.values()}
hiscore = 0
hiscoreUser = None
ambig = []
for user in users:
    userOrig = user
    user = user.removesuffix("_iosbackup")
    prevLen = len(user)
    user = user.removeprefix(queryUser)
    score = prevLen - len(user)
    #print(score)
    if score > 0 and score == hiscore: # TODO: untested if this detection works
        # Ambiguous user
        ambig.append(userOrig)
    if score > hiscore:
        hiscore = score
        hiscoreUser = userOrig
if hiscoreUser is None:
    print("Error: User starting with", queryUser, "not found")
    exit(1)
if len(ambig) > 0:
    print("Error: Ambiguous query: matches", ambig)
    exit(1)

print(hiscoreUser)
