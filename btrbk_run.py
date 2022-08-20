#! /usr/bin/env nix-shell
#! nix-shell --pure -i python3 ./shell.nix

import socket
import sys

exitCode = 1
eof = '__EOF__'

port = int(sys.argv[1])

# https://docs.python.org/3/howto/sockets.html
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as clientsocket:
    # bind the socket to a *local* host (public would be with `socket.gethostname()`), and a well-known port
    clientsocket.connect(('localhost', port))
    input_str = sys.stdin.read() # https://stackoverflow.com/questions/21235855/how-to-read-user-input-until-eof
    clientsocket.send(bytes(input_str + eof, 'utf-8'))
    # Get return code
    exitCode = int(clientsocket.recv(1024).decode('utf8'))

exit(exitCode)
