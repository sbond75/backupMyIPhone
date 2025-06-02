import sys
import os
import time

class Tee:
    def __init__(self, file, stream):
        self.file = file
        self.stream = stream

    def write(self, message):
        if message.strip() != "":
            timestamped = f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}"
        else:
            timestamped = message
        self.file.write(timestamped)
        self.stream.write(timestamped)

    def flush(self):
        self.file.flush()
        self.stream.flush()

# def setup_logging(logfile_path: str):
#     print("[ibackupClient] Starting logging to", logfile_path)
#     log_file = open(logfile_path, "w", buffering=1)  # line-buffered

#     sys.stdout = Tee(log_file, sys.__stdout__)
#     sys.stderr = Tee(log_file, sys.__stderr__)

# dup2's (works on windows/linux) to get stdout and stderr to go to stdout and stderr *but* also to the given log file path
def setup_logging(logfile_path: str):
    print(f"[ibackupClient] Starting logging to {logfile_path}")

    # Open log file and duplicate file descriptors
    log_file = open(logfile_path, 'w', buffering=1)
    log_fd = log_file.fileno()

    # Duplicate stdout and stderr to the log file (for subprocesses)
    os.dup2(log_fd, 1)  # fd 1 = stdout
    os.dup2(log_fd, 2)  # fd 2 = stderr

    # Replace sys.stdout and sys.stderr for Python prints (with timestamped Tee)
    sys.stdout = Tee(log_file, sys.__stdout__)
    sys.stderr = Tee(log_file, sys.__stderr__)
