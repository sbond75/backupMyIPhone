import os
import sys
import subprocess

def setup_logging(logfile: str):
    if "IBACKUP_TEE_STARTED" not in os.environ:
        # First execution -- re-run with tee-like logging
        print(f"[ibackupClient] Re-running with timestamped tee to {logfile}")

        env = os.environ.copy()
        env["IBACKUP_TEE_STARTED"] = "1"

        # Re-run this script via subprocess, capturing output
        process = subprocess.Popen(
            [sys.executable] + sys.argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env
        )

        # Open log file for writing
        assert process.stdout is not None
        with open(logfile, "w", buffering=1) as log_file:
            for line in process.stdout:
                from time import strftime
                timestamped = f"{strftime('%Y-%m-%d %H:%M:%S')} {line}"
                print(timestamped, end='')       # Print to terminal
                log_file.write(timestamped)      # Write to file

        process.wait()
        sys.exit(process.returncode)

    # This is the second run: continue with actual logic
    # (We return to do that)
