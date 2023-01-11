#! /usr/bin/env nix-shell
#! nix-shell --pure -i python3 ./shell.nix

import os
import sys

# Check if root
uid = os.getuid()
if uid != 0:
    print("This script must be run as root. Exiting.")
    exit(1)

# # https://stackoverflow.com/questions/107705/disable-output-buffering #
# import functools
# print = functools.partial(print, flush=True)
# # #

# # https://stackoverflow.com/questions/107705/disable-output-buffering #
# class Unbuffered(object):
#    def __init__(self, stream):
#        self.stream = stream
#    def write(self, data):
#        self.stream.write(data)
#        self.stream.flush()
#    def writelines(self, datas):
#        self.stream.writelines(datas)
#        self.stream.flush()
#    def __getattr__(self, attr):
#        return getattr(self.stream, attr)
# import sys
# sys.stdout = Unbuffered(sys.stdout)
# sys.stderr = Unbuffered(sys.stderr)
# # #

from datetime import datetime

# https://stackoverflow.com/questions/58162544/adding-timestamp-to-print-function
old_print = print
def timestamped_print(*args, **kwargs):
    old_print(datetime.now(), *args, **kwargs)
print = timestamped_print

# Make logfile name
LOGS_PATH = '/mnt/ironwolf/home/iosbackup_usbmuxd/logs/'
now = datetime.now()
LOG_NAME = LOGS_PATH + now.strftime("%Y-%m-%d_%H_%M_%S") + '.log_btrbk_daemon.txt'

# # https://stackoverflow.com/questions/616645/how-to-duplicate-sys-stdout-to-a-log-file #
# # open our log file
# so = se = open(LOG_NAME, 'w', 0)

# # re-open stdout without buffering
# sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', 0)
# sys.stderr = os.fdopen(sys.stderr.fileno(), 'w', 0)

# # redirect stdout and stderr to the log file opened above
# os.dup2(so.fileno(), sys.stdout.fileno())
# os.dup2(se.fileno(), sys.stderr.fileno())
# # #

# # Based on https://stackoverflow.com/questions/4675728/redirect-stdout-to-a-file-in-python #
# old = os.dup(1)
# sys.stdout.flush()
# os.close(1)
# fd = os.open(LOG_NAME, os.O_WRONLY | os.O_CREAT)
# assert(fd == 1) # should open on 1

# old = os.dup(2)
# sys.stderr.flush()
# os.close(2)
# fd = os.open(LOG_NAME, os.O_WRONLY | os.O_CREAT)
# assert(fd == 2) # should open on 2
# # #

# # https://stackoverflow.com/questions/38776104/redirect-stdout-and-stderr-to-same-file-using-python #
# sys.stdout = open(LOG_NAME, 'w')
# sys.stderr = sys.stdout
# # #

# Based on https://www.cs.utexas.edu/~theksong/2020/243/Using-dup2-to-redirect-output/ and https://stackoverflow.com/questions/616645/how-to-duplicate-sys-stdout-to-a-log-file #
fd = os.open(LOG_NAME, os.O_WRONLY | os.O_CREAT, 0o644); # rw-r--r--   # https://chmod-calculator.com/
os.dup2(fd, sys.stdout.fileno())
os.dup2(fd, sys.stderr.fileno())
# #

import subprocess
import socket
import shlex
import grp
import pwd

requiredUserID = sys.argv[1] # Leave as an empty string to ignore this
requiredCommandName = sys.argv[2] # This is for the parent of the connecting process only   # Leave as an empty string to ignore this
dryRun = True if sys.argv[3] == '1' else False
port = int(sys.argv[4])

# https://docs.python.org/3/howto/sockets.html
#with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as serversocket:
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as serversocket:
    # bind the socket to a public host, and a well-known port
    serversocket.bind(('localhost', port))
    # become a server socket
    serversocket.listen(5)#1)   #serversocket.listen(5) # "Finally, the argument to listen tells the socket library that we want it to queue up as many as 5 connect requests (the normal max) before refusing outside connections. If the rest of the code is written properly, that should be plenty."
    
    myPID = os.getpid()
    
    while True:
        # accept connections from outside
        clientsocket = None
        userID = None
        try:
            print("listening...")
            clientsocket, address = serversocket.accept()
            address = 'localhost'
            port = clientsocket.getsockname()[1] # https://stackoverflow.com/questions/37360682/sockets-programming-with-python-get-the-port-of-a-server
            print("port:",port)
            # Find out who made this connection
            fmtString = 'pgcuL'
            stdout=subprocess.check_output(['lsof', '-F', fmtString, f"-iTCP@{address}:{port}"]).decode("utf-8")
            print(stdout)
            lines=stdout.splitlines()
            i = 0
            valid = False # Assume False
            for line in lines:
                if line.startswith('p'):
                    pid = int(line.lstrip('p'))
                    if pid == myPID:
                        i += 1
                        continue
                    # Check if this PID is valid to communicate with
                    #commandName = lines[i+fmtString.index('c')][1:]
                    # https://stackoverflow.com/questions/1525605/programmatically-get-parent-pid-of-another-process
                    with open(f"/proc/{pid}/stat", "r") as f:
                        parentPID=f.read().split()[3]
                    # https://stackoverflow.com/questions/606041/how-do-i-get-the-path-of-a-process-in-unix-linux
                    #commandName = os.readlink(f"/proc/{parentPID}/exe")
                    with open(f"/proc/{parentPID}/cmdline", "r") as f:
                        commandName=f.read().split('\0')[0] #' '.join(f.read().split('\0'))
                    loginName = lines[i+fmtString.index('L')][1:]
                    userID = lines[i+fmtString.index('u')][1:] # This is the uid of the user
                    processGroupID = lines[i+fmtString.index('g')][1:] # Note: this is unrelated to user's group, it is process group I think..

                    # # This only seems to return the first group ID like 100 which is `users` instead of iosbackup:
                    # groupID = pwd.getpwuid(int(userID)).pw_gid # https://stackoverflow.com/questions/9323834/python-how-to-get-group-ids-of-one-username-like-id-gn , https://docs.python.org/3/library/pwd.html
                    # # ^ so, we do this too:
                    # groupIDs = grp.getgrall()
                    # for row in groupIDs: # https://www.geeksforgeeks.org/grp-module-in-python/
                    #     if row.gr_name == 'iosbackup' and userID in row.gr_mem:
                    #         groupID = row.gr_gid

                    groupName = 'iosbackup' if ('iosbackup' in map(lambda x: x.rstrip('\n'), subprocess.check_output(['groups', loginName]).decode("utf-8").split(' '))) else None
                    
                    #groupName = grp.getgrgid(groupID).gr_name
                    print(lines[i+fmtString.index('c')][1:], commandName, loginName, userID,
                          #groupID,
                          groupName)
                    if groupName == 'iosbackup' and (userID == requiredUserID or requiredUserID == '') and (commandName == requiredCommandName or requiredCommandName == ''):
                        valid = True
                        break
                i +=1

            if not valid:
                print("invalid connecting process")
                continue
            
            # Get its btrbk config (end with '__EOF__' text)
            eof='__EOF__'
            btrbkConfig = ''
            while True:
                part = clientsocket.recv(1024)
                if part:
                    btrbkConfig += part.decode("utf-8")
                else:
                    print("didn't recv() enough")
                    break
                if part.decode("utf-8").endswith(eof):
                    break
            btrbkConfig = btrbkConfig[:-len(eof)] # https://www.geeksforgeeks.org/python-remove-the-given-substring-from-end-of-string/

            # Ensure it is trying to get the right stuff
            fields = btrbkConfig.splitlines()
            def grabField(toFind,index=0): # index = the line index in `fields` above from which to start searching
                i = index
                while i < len(fields):
                    line = fields[i] + '\n'
                    f=line.find(toFind)
                    #if f == -1:
                    if line.strip().split()[0] != toFind:
                        i += 1
                        continue
                    j = line.find('\n',f+len(toFind))
                    if j != -1:
                        return line[f+len(toFind):j].strip(), i
                    i += 1
                # Not found
                raise Exception("Field not found in line " + str(index+1) + ": " + str(toFind))
            logfile,i = grabField('transaction_log')
            if not logfile.startswith(LOGS_PATH):
                print("invalid command: transaction_log:", logfile)
                continue
            snapshotDir,i = grabField('snapshot_dir', i)
            if snapshotDir != f"home/{loginName}/_btrbk_snap":
                print("invalid command: snapshot_dir:", snapshotDir)
                continue
            volume,i = grabField('volume', i)
            if volume != '/mnt/ironwolf':
                print("invalid command: volume:", volume)
                continue
            subvolume,i = grabField('subvolume', i)
            if subvolume != f"home/{loginName}/@iosBackups":
                print("invalid command: subvolume:", subvolume)
                continue

            # Run
            print("Running:")
            proc = subprocess.run(['bash', '-c', 'btrbk --config=<(echo "$0") --verbose --preserve --preserve-backups --preserve-snapshots ' + ("dryrun" if dryRun else "run"), btrbkConfig])
            ret = proc.returncode
            print("process", proc.args, "returned", ret)
            # Inform the program on the other end of the socket that btrbk succeeded or failed
            clientsocket.send(str(ret).encode('utf8')) # https://stackoverflow.com/questions/33913308/socket-module-how-to-send-integer
        except KeyboardInterrupt:
            break
        except:
            import traceback
            print("Caught exception:")
            traceback.print_exc()
        finally:
            if clientsocket is not None:
                clientsocket.close()
