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

def setup_logging(logfile_path: str):
    print("[ibackupClient] Starting logging to", logfile_path)
    log_file = open(logfile_path, "w", buffering=1)  # line-buffered

    sys.stdout = Tee(log_file, sys.__stdout__)
    sys.stderr = Tee(log_file, sys.__stderr__)
