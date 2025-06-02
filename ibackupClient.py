#!/usr/bin/env python3

import os
import sys
import subprocess
import datetime
import shutil
import signal
import re
from pathlib import Path
from ibackupServer import parse_config
import udidToFolderLookupTable
import time
from LEDState import LEDState
import argparse
import threading
import atexit
import traceback
from typing import Union

# =========================
# Signal handling, exception handling, and atexit stuff
# =========================

# Global flags to track thread exceptions, unhandled exceptions, and signals
thread_exception_occurred = False
unhandled_exception_occurred = False
signal_termination_occurred = False

# A list to store all registered handlers for a given signal
signal_handlers = []

def main_signal_handler(signum, frame):
    """
    Main signal handler that dispatches the signal to all registered handlers.
    """
    print(f"Signal received: {signum}")
    for handler in signal_handlers:
        handler(signum, frame)

signal.signal(signal.SIGINT, main_signal_handler)  # Handle Ctrl+C
signal.signal(signal.SIGTERM, main_signal_handler)  # Handle termination signal

# Custom handler for unhandled exceptions in the main thread
def handle_unhandled_exception(exc_type, exc_value, exc_traceback):
    global unhandled_exception_occurred
    unhandled_exception_occurred = True

    # Log the exception type, value, and traceback
    print("[ibackupClient] Unhandled exception occurred!")
    print(f"[ibackupClient] Type: {exc_type}")
    print(f"[ibackupClient] Value: {exc_value}")
    print("[ibackupClient] Traceback:")
    #traceback.print_tb(exc_traceback)
    traceback.print_exception(exc_type, exc_value, exc_traceback)

    # You can perform additional cleanup or logging here
    # For example, releasing resources or saving state

# Set the custom exception hook for the main thread
sys.excepthook = handle_unhandled_exception

# Custom handler for thread exceptions (only for within a `threading.Thread.run`) (Python 3.8+)
def handle_thread_exception(args):
    global thread_exception_occurred
    thread_exception_occurred = True

    # Log the exception type, value, and traceback
    print("[ibackupClient] Unhandled exception occurred!")
    print(f"[ibackupClient] Thread name: {args.thread.name}")
    print(f"[ibackupClient] Exception type: {args.exc_type}")
    print(f"[ibackupClient] Exception value: {args.exc_value}")
    print("[ibackupClient] Traceback:")
    #traceback.print_tb(args.exc_traceback)
    traceback.print_exception(args.exc_type, args.exc_value, args.exc_traceback)

# Set the custom exception hook for threads
threading.excepthook = handle_thread_exception

_led_state = None

# Atexit handler
def on_exit():
    global unhandled_exception_occurred, signal_termination_occurred, thread_exception_occurred

    # Indicate error on LED if any
    if unhandled_exception_occurred or thread_exception_occurred:
        # slow blink to indicate exception
        if _led_state is not None and _led_state.indicate:
            print("[ibackupClient] Setting LED very slow blink (every 2 seconds) in atexit handler.")
            _led_state.start_blinking(2)

    # Check if an exception or signal occurred
    if unhandled_exception_occurred:
        print("[ibackupClient] Exiting due to unhandled exception.")
        return
    if signal_termination_occurred:
        print("[ibackupClient] Exiting due to signal termination.")
    if thread_exception_occurred:
        print("[ibackupClient] Exiting due to thread exception.")
        return

    if _led_state is not None and _led_state.indicate:
        # # Turn led_state off
        # _led_state.solid_off()

        _led_state.reset_led()

        # Perform normal cleanup if no exceptions or signals occurred
        print("[ibackupClient] Setting normal LED in atexit handler.")

    print("[ibackupClient] No error in atexit handler.")

# Register the atexit handler
atexit.register(on_exit)

# Signal handler for SIGINT and SIGTERM
def handle_signal(signum, frame):
    global signal_termination_occurred
    signal_termination_occurred = True

    # Log the signal
    print(f"[ibackupClient] Received signal: {signum}. Exiting gracefully...")

    # Exit abruptly to skip atexit handlers (optional)
    # os._exit(0)

# Register signal handlers
signal_handlers.append(handle_signal)

# =========================
# Lib
# =========================

def runCmd(first_arg, *args, **kwargs):
    print("[ibackupClient] Running command:", first_arg.join(' '))
    return subprocess.run(first_arg, *args, **kwargs)

def callCmd(first_arg, *args, **kwargs):
    print("[ibackupClient] Running command:", first_arg.join(' '))
    return subprocess.call(first_arg, *args, **kwargs)

def popenCmd(first_arg, *args, **kwargs):
    print("[ibackupClient] Running command:", first_arg.join(' '))
    return subprocess.Popen(first_arg, *args, **kwargs)

# =========================
# Script Arguments (Globals)
# =========================

parser = argparse.ArgumentParser(description="ibackupClient script")

parser.add_argument("--first-time", action='store_true',
                    help="Indicates if first time backup")
parser.add_argument("--indicate-on-led", action='store_true',
                    help="Enable LED indication")
parser.add_argument("--skip-actual-backup", action='store_true',
                    help="Skip making a backup of the iOS device")
parser.add_argument("--backup-folder", type=str,
                    help="Just back up a specific folder and do nothing else")
parser.add_argument("--backup-label", type=str,
                    help="Label for the backup made with `--backup-folder`")

# Add the --logging flag, defaulting to True
parser.add_argument(
    '--logging',
    action='store_true',  # If --logging is passed, logging will be True
    default=True,         # Default value is True
    help='Enable logging (default: enabled)'
)
# Add the --no-logging flag, which negates --logging
parser.add_argument(
    '--no-logging',
    action='store_false', # If --no-logging is passed, logging will be False
    dest='logging',       # Both flags modify the same `logging` variable
    help='Disable logging'
)

# =========================
# Global State Definition
# =========================

class GlobalState:
    def __init__(self, config_dict):
        self.configDict = config_dict
        self.udid_table_keys_array = list(udidToFolderLookupTable.lookupTable.keys())
        self.backup_pid: list[None|threading.Thread] = [None] * len(self.udid_table_keys_array)

# =========================
# LED Setup
# =========================

def prepare_led_permissions(indicate):
    led = "/sys/class/leds/led0/trigger"
    led1 = "/sys/class/leds/PWR/brightness"
    led_trigger1 = "/sys/class/leds/PWR/trigger"

    if indicate:
        user = os.getenv("USER")
        assert user is not None

        paths = [led, led_trigger1, led1]
        for path in paths:
            if not os.access(path, os.W_OK):
                print(f"[ibackupClient] Running chown {user} {path}")
                runCmd(["sudo", "chown", user, path], check=True)
        with open(led1, "w") as f:
            f.write("0")
        #atexit.register(reset_led)

    led_state = LEDState(led1, led_trigger1, indicate=indicate)
    def reset_led():
        if indicate:
            print("[ibackupClient] Resetting led1 to normal")
            with open(led_trigger1, "w") as f:
                f.write("input")
    led_state.reset_led = reset_led
    return led_state

# =========================
# Prepare PID Tables
# =========================

def lookup_username(st: GlobalState, udid: str) -> str:
    return udidToFolderLookupTable.lookupTable[udid]

# =========================
# Backing up
# =========================

def pair_and_enable_encryption(udid: str, first_time: bool) -> bool:
    """
    Pairs with the device and enables backup encryption.
    
    Returns True if pairing and encryption succeeded (or was already enabled), else False.
    """
    if not first_time:
        return True

    # ----- Pairing Loop -----
    print(f"[ibackupClient] Attempting to pair with device {udid}")
    exit_code = callCmd(["idevicepair", "--udid", udid, "pair"])
    attempt = 2
    while exit_code != 0:
        sleep_time = 8
        print(f"[ibackupClient] Sleeping for {sleep_time} seconds...")
        time.sleep(sleep_time)
        print(f"[ibackupClient] Retrying pair for {udid} after failing with exit code {exit_code} (attempt {attempt})")
        exit_code = callCmd(["idevicepair", "--udid", udid, "pair"])
        attempt += 1

    # ----- Enable Encryption -----
    print(f"[ibackupClient] Enabling backup encryption for {udid}")
    force_success = False

    process = popenCmd(
        ["idevicebackup2", "--udid", udid, "-i", "encryption", "on"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )

    assert process.stdout is not None
    for line in process.stdout:
        print(line.strip())
        if "ERROR: Backup encryption is already enabled. Aborting." in line:
            force_success = True

    exit_code = process.wait()
    if exit_code != 0 and not force_success:
        print(f"[ibackupClient] Enabling encryption failed with exit code {exit_code}. Skipping this backup.")
        return False

    if exit_code == 0 and not force_success:
        try:
            user_input = input(
                "Enable or change backup password (needed to get Health data like steps, WiFi settings, call history, etc. -- https://support.apple.com/en-us/HT205220) (y/n)? "
            ).strip()
        except EOFError:
            user_input = "n"

        if user_input.lower() == 'y':
            result = callCmd(["idevicebackup2", "--udid", udid, "-i", "changepw"])
            if result != 0:
                print(f"[ibackupClient] Setting backup password failed with exit code {result}. Skipping this backup.")
                return False

    print("[ibackupClient] Pairing and encryption complete.")
    return True


def prepare_backup_path(st: GlobalState, udid: str, first_time: bool) -> Union[Path, None]:
    """
    Prepares the full path to where the iOS backup should be stored.
    
    Args:
        st (GlobalState): The global state object.
        udid (str): The UDID of the connected iOS device (with dashes).
        first_time (bool): True if it's the first time the script is being run.
    
    Returns:
        Path: The full destination path.
    """

    # Look up username and normalize
    user_folder_name = lookup_username(st, udid)
    user_folder_name = udidToFolderLookupTable.removeDashes_(user_folder_name)
    print(f"[ibackupClient] User folder name: {user_folder_name}")

    dest_full = Path(st.configDict['config__localDiskPath']) / user_folder_name

    # Mount disk if specified
    made_disk_mount = False
    if st.configDict.get('config__localDisk') is not None:
        try:
            runCmd(
                ["mountpoint", st.configDict['config__localDisk']],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
        except subprocess.CalledProcessError:
            try:
                made_disk_mount = True
                print(f"[ibackupClient] Mounting {st.configDict['config__localDisk']} from {st.configDict['config__localDiskDevice']}")
                runCmd(["sudo", "mkdir", "-p", st.configDict['config__localDisk']], check=True)
                runCmd(["sudo", "mount", st.configDict['config__localDiskDevice'], st.configDict['config__localDisk']], check=True)
            except subprocess.CalledProcessError:
                print("Error: failed to mount backup destination drive. Not backing up this device for now.")
                return None

    # Make destination directory
    if first_time or made_disk_mount:
        runCmd(["sudo", "mkdir", "-p", str(dest_full)], check=True)
        user = os.getenv("USER")
        assert user is not None
        runCmd(["sudo", "chown", "-R", user, st.configDict['config__localDiskPath']], check=True)
    else:
        dest_full.mkdir(parents=True, exist_ok=True)

    return dest_full

def run_backup(
    udid: str,
    dest_full: str,
    skip_actual_backup: bool,
    starting_backup_led,
    finished_backup_led
) -> int:
    """
    Runs the backup process.

    Args:
        udid: Device UDID to back up.
        dest_full: Destination path for backup.
        skip_actual_backup: If True, skip the actual backup step.
        starting_backup_led: Function that runs when backup starts.
        finished_backup_led: Function that runs when backup ends. Is given a bool where True means success.

    Returns:
        Exit code of the backup operation (0 = success, non-zero = failure).
    """

    if skip_actual_backup:
        print("[ibackupClient] Backup skipped due to `skipActualBackup` being 1.")
        return 0

    print("[ibackupClient] Starting backup.")
    starting_backup_led()

    # Directly execute and stream output
    result = runCmd(
        ["idevicebackup2", "--udid", udid, "backup", dest_full]
    )

    finished_backup_led(result.returncode == 0)

    print(f"[ibackupClient] Backup finished with exit code {result.returncode}.")
    return result.returncode

# =========================
# Borg backup
# =========================

# Backs up the `directory`.
def run_borg_backup(directory, sshUser, ip, port, remote_repo_path, remote_backup_label
#, password
, borg_lock: threading.Lock):
    with borg_lock:  # <--- critical section protected by mutex
        # # This is the dir to back up.
        # os.chdir(directory)

        # Generate timestamp in the format: YYYY-MM-DD-HH:MM:SS.nanoseconds
        dt = datetime.datetime.now().strftime('%Y-%m-%d-%H:%M:%S.%f')  # .%f gives microseconds
        dt = dt[:-3] + '000'  # Extend to nanoseconds (fake nanosecond resolution, just pad zeros)

        # Construct full backup path
        repo = f"ssh://{sshUser}@{ip}:{port}/{remote_repo_path}::{dt}_{remote_backup_label}"

        env = os.environ.copy()
        # env["BORG_PASSPHRASE"] = password

        # Run the borg backup command
        result = runCmd([
            "borg",
            "create",
            "--stats",
            "--progress",
            "--compression", "auto,lz4",
            "--remote-path", "/nix/store/yng7ci969cibdpnjxbmdm6s64i9jl0hp-borgbackup-1.2.3/bin/borg",
            repo,
            directory
        ], env=env, check=True)

        return result.returncode

# Backs up the `directory`.
def run_borg_backup_highlevel(st: GlobalState, directory, label, borg_lock: threading.Lock):
    run_borg_backup(
        directory=directory,
        sshUser=st.configDict['config__borgBackupUser'],
        ip=st.configDict['config__borgBackupIP'],
        port=st.configDict['config__borgBackupPort'],
        remote_repo_path=st.configDict['config__borgRepoPath'],
        remote_backup_label=label,
        # password=st.configDict['config__borgSSHPassword'],
        borg_lock=borg_lock
    )

# =========================
# Device Parser
# =========================

def parse_output(st: GlobalState, led_state: LEDState, first_time, skip_actual_backup, script_dir):
    regex = re.compile(r"^(?:\[\d+:\d+:\d+\.\d+\]\[\d+\] )?Got serial '([^']*)' for device .*$")

    def signal_handler(sig, frame):
        print("[ibackupClient] Signal received, killing background jobs")
        
        for pid in st.backup_pid:
            if pid and pid.is_alive():
                print(f"[ibackupClient] Attempting to join thread {pid.name}")
                pid.join(timeout=1)
        led_state.solid_off()
        sys.exit(0)

    signal_handlers.append(signal_handler)

    usbmuxd = shutil.which("usbmuxd")
    assert usbmuxd is not None
    process = popenCmd(
        ["sudo", usbmuxd, "--foreground", "-v"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )

    borg_lock = threading.Lock()

    assert process.stdout is not None
    for line in process.stdout:
        print(line, end="")
        match = regex.match(line)
        if not match:
            continue

        udid = match.group(1)
        print(f"[ibackupClient] Device found: {udid}")
        udid = udid[:8] + "-" + udid[8:]

        username = lookup_username(st, udid)

        skip = False
        for i, key in enumerate(st.udid_table_keys_array):
            if key == udid and st.backup_pid[i]:
                print(f"[ibackupClient] Backup process for {udid} is already running.")
                skip = True
                break

        if skip:
            continue

        success = pair_and_enable_encryption(udid=udid, first_time=first_time)
        if not success:
            print(f"[ibackupClient] Skipping backup for {udid} due to pairing/encryption failure.")
            continue

        # Do backup ####################################################################################

        # Prepare backup path
        dest_full = prepare_backup_path(st, udid, first_time)
        assert dest_full is not None

        def backup_thread():
            success = run_backup(
                udid=udid,
                dest_full=str(dest_full),
                skip_actual_backup=skip_actual_backup,
                starting_backup_led=lambda: led_state.solid_on(),
                finished_backup_led=lambda success: led_state.solid_off() if success else led_state.start_blinking(0.1), # rapid blink for error indication if error occurred
            ) == 0
            
            if success:
                # Save the backup with Borg
                run_borg_backup_highlevel(st, directory=dest_full, label='AutomaticBackup_' + username + "_" + udid, borg_lock=borg_lock)

        t = threading.Thread(target=backup_thread, name=f"backup-{udid}")
        t.start()

        for i, key in enumerate(st.udid_table_keys_array):
            if key == udid:
                st.backup_pid[i] = t
                break
        else:
            print(f"[ibackupClient] Warning: Couldn't save thread for UDID {udid}")

# =========================
# Logging setup
# =========================

# dup2's (works on windows/linux) to get stdout and stderr to go to stdout and stderr *but* also to the given log file path
def setup_logging(logfile_path: str):
    log_file = open(logfile_path, "a")  # or "w" to overwrite each time

    # Duplicate the file descriptor to both stdout and stderr
    log_fd = log_file.fileno()
    
    sys.stdout.flush()
    sys.stderr.flush()

    os.dup2(log_fd, 1)  # stdout
    os.dup2(log_fd, 2)  # stderr

    # Optionally wrap the file in a stream for sys.stdout/sys.stderr
    sys.stdout = os.fdopen(1, 'w', buffering=1)
    sys.stderr = os.fdopen(2, 'w', buffering=1)

# =========================
# Run
# =========================

def run():
    args = parser.parse_args()

    first_time = args.first_time
    indicate_on_led = args.indicate_on_led
    skip_actual_backup = args.skip_actual_backup
    backup_folder = args.backup_folder
    backup_label = args.backup_label
    logging = args.logging

    # Prepare to run
    if (sys.platform == 'linux' or sys.platform == 'darwin') and os.geteuid() == 0:
        print("This script should ideally be run as a non-root user. Exiting.")
        sys.exit(1)

    # Sync network time
    runCmd(["timedatectl"], check=True)

    scriptPath = os.path.dirname(os.path.realpath(__file__))
    configPath = os.path.join(scriptPath, "config.sh")
    config_dict = parse_config(configPath)

    if logging:
        dest = Path(config_dict['config__clientDirectory'])
        dest.mkdir(parents=True, exist_ok=True)

        logs_dir = dest / "ibackupClientPy_logs"
        logs_dir.mkdir(parents=True, exist_ok=True)
        logfile = logs_dir / datetime.datetime.now().strftime("%Y-%m-%d %I-%M-%S %p.log.txt")

        # Set up logging
        setup_logging(str(logfile))

    # Set up LEDs
    led_state = prepare_led_permissions(indicate_on_led)
    global _led_state
    _led_state = led_state

    st = GlobalState(config_dict)
    if backup_folder is not None:
        assert backup_label is not None

        # Just back up the given folder:
        borg_lock = threading.Lock()
        run_borg_backup_highlevel(st, backup_folder, backup_label, borg_lock)
    else:
        # Run usbmuxd output parser
        parse_output(
            st=st,
            led_state=led_state,
            first_time=first_time,
            skip_actual_backup=skip_actual_backup,
            script_dir=scriptPath
        )

if __name__ == '__main__':
    run()
