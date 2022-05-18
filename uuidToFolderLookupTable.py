#! /usr/bin/env nix-shell
#! nix-shell -i python -p python3

from sys import argv

lookupTable={
        "00008110-001C2CD23AD1801E": "sebastian",
}

return lookupTable[argv[1]]
