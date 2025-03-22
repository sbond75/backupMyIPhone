#! /usr/bin/env nix-shell
#! nix-shell shell_ibackupServer.nix -i python3

import os
import socket
import subprocess
import sys
import re
from shlex import quote
import udidToFolderLookupTable
import traceback

# Grab paths to stuff
bindfsPath = subprocess.run(["which", "bindfs"], capture_output=True, check=True, text=True).stdout[:-1] # (trim trailing newline)
umountPath = subprocess.run(["which", "umount"], capture_output=True, check=True, text=True).stdout[:-1] # (trim trailing newline)
sudoPath = subprocess.run(["which", "sudo"], capture_output=True, check=True, text=True).stdout[:-1] # (trim trailing newline)
if sudoPath.startswith('/nix/store/'): # NixOS-specific hack
    sudoPath = "/run/wrappers/bin/sudo"
mountpointPath = subprocess.run(["which", "mountpoint"], capture_output=True, check=True, text=True).stdout[:-1] # (trim trailing newline)

class BackupStatus:
    def __init__(self):
        self.status = {}

    def set_was_backed_up(self, udid, status):
        self.status[udid] = status

    def was_backed_up(self, udid):
        res = self.status.get(udid)
        if res is None:
            return "0"
        return res

class GlobalState:
    def __init__(self, config_dict, scriptPath):
        self.configDict = config_dict
        self.tcpPort = int(config_dict['config__serverCommands_port'])
        self.scriptPath = scriptPath
        self.destDrive = config_dict['config__drive']
        self.backupStatus = BackupStatus()

        # Add `scriptPath` to python import path:
        print("Inserting module path:", self.scriptPath)
        sys.path.insert(0, self.scriptPath)

        #sys.path.insert(0, '') # add current directory to python import path

    def scriptDirPath(self, p):
        return os.path.join(self.scriptPath, p)

# Made by ChatGPT-4o.
# Performs basic bash file parsing.
def parse_config(file_path):
    config_dict = {}
    variable_pattern = re.compile(r'\$([a-zA-Z_][0-9a-zA-Z_]*)')
    
    with open(file_path, 'r') as file:
        for line in file:
            # Remove leading/trailing whitespace
            line = line.strip()
            
            # Skip empty lines and comments (lines starting with '#')
            if not line or line.startswith('#'):
                continue
            
            # Split the line into key and value
            if '=' in line:
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip()
                
                # Perform variable substitution
                def substitute_variable(match):
                    var_name = match.group(1)
                    # Replace with the corresponding value from the dictionary, or keep the variable if not found
                    return config_dict.get(var_name, f'${var_name}')
                
                # Replace all variables in the value
                value = variable_pattern.sub(substitute_variable, value)
                
                # Store the key-value pair
                config_dict[key] = value
    
    return config_dict

def callBashFunction():
    pass

# Made mostly by ChatGPT-4o #
def get_vars(st: GlobalState, udid):
    username = lookup_username(st, udid)
    username_ftp = f"{username}_ftp"
    dest = f"{st.destDrive}/home/{username}/@iosBackups"
    return username, username_ftp, dest

def lookup_username(st: GlobalState, udid):
    # # Simulates the Python script that maps UDID to user
    # return subprocess.check_output(["python3", st.scriptDirPath("udidToFolderLookupTable.py"), udid]).decode().strip()

    # print("sys.path:", sys.path)
    return udidToFolderLookupTable.lookupTable[udid]

def runCmd(argList):
    print('[ibackupServer] Running command:', argList)

    # print("Environment Variables:")
    # for key, value in os.environ.items():
    #     print(f"{key}={value}")
    
    # # Quote each argument to make it safe for shell execution
    # command_str = " ".join(quote(arg) for arg in argList)

    # (`shell=True` is needed due to sudoers being used)
    #return subprocess.run(command_str, shell=True, check=True)
    
    #result = subprocess.run(command_str, shell=True, check=True, capture_output=True, text=True)
    #print(result.stdout, '|', result.stderr)
    #return result

    #return subprocess.run(argList, stdout=sys.stdout, stderr=sys.stderr, shell=False, check=True)

    sys.stdout.flush()
    sys.stderr.flush()
    return subprocess.run(argList, shell=False, check=True)

def unmount(username_ftp):
    runCmd([sudoPath
        #, "umount"
        , umountPath, "-f"
        , f"/home/{username_ftp}"]) # (`sudo` is used; this requires a sudoers entry -- see README.md under the `## Server-client mode` section for more info)

def start_backup(st: GlobalState, udid):
    username, username_ftp, dest = get_vars(st, udid)
    print(f"[ibackupServer] Opening vsftpd for user {username_ftp} with device UDID {udid}")

    if not os.path.exists(dest):
        print(f"[ibackupServer] Error: {dest} doesn't exist. Not starting backup.")
        st.backupStatus.set_was_backed_up(udid, "0")
    else:
        # Check if it is mounted
        try:
            runCmd([sudoPath
                    , mountpointPath
                    , f"/home/{username_ftp}"])
            mounted = True
        except subprocess.CalledProcessError:
            # It isn't mounted
            mounted = False

        if not mounted:
            # Bind user directory with bindfs (requires sudo)
            runCmd([sudoPath
                    , bindfsPath
                    , f"--map={username}/{username_ftp}", dest, f"/home/{username_ftp}"]) # (`sudo` is used; this requires a sudoers entry -- see README.md under the `## Server-client mode` section for more info)

            # # Bind user directory with bindfs (requires sudo)
            # retry = True
            # tries=0
            # while retry:
            #     try:
            #         tries += 1
            #         runCmd([sudoPath
            #                 #, "bindfs"
            #                 , bindfsPath
            #                 , f"--map={username}/{username_ftp}", dest, f"/home/{username_ftp}"]) # (`sudo` is used; this requires a sudoers entry -- see README.md under the `## Server-client mode` section for more info)
            #         retry = False
            #     except subprocess.CalledProcessError:
            #         if tries > 1:
            #             print('[ibackupServer] Failed to run bindfs again, will raise exception')
            #             raise

            #         # Exit code was non-zero, try unmounting first:
            #         print('[ibackupServer] Failed to run bindfs, will try unmounting first')
            #         unmount(username_ftp)
            #         retry = True

        st.backupStatus.set_was_backed_up(udid, "s")
        print(f"[ibackupServer] Started vsftpd for user {username_ftp} with device UDID {udid}.")

def finish_backup(st: GlobalState, udid, unsuccessful):
    status = st.backupStatus.was_backed_up(udid)
    if status != "s":
        if unsuccessful:
            print(f"[ibackupServer] Backup for UDID {udid} is not currently started; can't finishBackupUnsuccessful.")
        else:
            print(f"[ibackupServer] Backup for UDID {udid} is not currently started; can't finishBackup.")
        return

    username, username_ftp, dest = get_vars(st, udid)
    if not unsuccessful:
        make_snapshot(os.path.dirname(dest), username)

    # Unmount bindfs
    unmount(username_ftp)
    st.backupStatus.set_was_backed_up(udid, "f")
    print(f"[ibackupServer] Stopped vsftpd for user {username_ftp} with device UDID {udid}.")

def make_snapshot(st: GlobalState, dest, username):
    print(f"Creating snapshot of {dest}")

    # Load bash script
    subprocess.run(["bash", "-c", f"""
    source {quote(st.scriptDirPath('makeSnapshot.sh'))}
    
    # Prepare variables
    source {quote(st.scriptDirPath('config.sh'))}
    username={quote(username)}

    makeSnapshot {quote(dest)}
    """], check=True) # (`sudo` is used; this requires a sudoers entry -- see README.md under the `## Server-client mode` section for more info)

def process_command(st: GlobalState, command):
    parts = command.strip().split()
    if len(parts) < 2:
        print(f"[ibackupServer] Unknown command: {command}")
        return

    cmd, udid = parts[0], parts[1]
    if cmd == "startBackup":
        if st.backupStatus.was_backed_up(udid) == "0":
            start_backup(st, udid)
        else:
            print("[ibackupServer] Backup is already \"started\", nothing to do. It must have been left on or something...")
    elif cmd == "finishBackup":
        finish_backup(st, udid, unsuccessful=False)
    elif cmd == "finishBackupUnsuccessful":
        finish_backup(st, udid, unsuccessful=True)
    else:
        print(f"[ibackupServer] Unknown command: {command}")

def shutdown(st: GlobalState):
    print("Begin clean shutdown:")
    for udid, username in udidToFolderLookupTable.lookupTable.items():
        finish_backup(st, udid, False)

def runCommandProcessor(st: GlobalState):
    try:
        # Listen for incoming connections and process commands
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(('0.0.0.0', st.tcpPort))
            s.listen()
            print(f"[ibackupServer] Listening on port {st.tcpPort}")

            while True:
                conn, addr = s.accept()
                with conn:
                    print(f"Connected by {addr}")
                    data = conn.recv(1024)
                    if not data:
                        break
                    command = data.decode('utf-8')
                    process_command(st, command)
                    conn.sendall(b"Command processed.\n")
    except:
        sys.stdout.flush()
        sys.stderr.flush()
        print("Command processor is handling the following exception by cleanly shutting down:")
        sys.stdout.flush()
        traceback.print_exc()
    finally:
        shutdown(st)
# #

def run():
    scriptPath = os.path.dirname(os.path.realpath(__file__))
    configPath = os.path.join(scriptPath, "config.sh")
    config_dict = parse_config(configPath)

    st = GlobalState(config_dict, scriptPath)
    runCommandProcessor(st)

if __name__ == '__main__':
    run()
