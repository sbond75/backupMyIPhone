import os
import sys
import subprocess
import signal

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

        # # Signal forwarding handler
        # def forward_signal(signum, frame):
        #     # Forward the signal to child
        #     try:
        #         process.send_signal(signum)
        #     except ProcessLookupError:
        #         pass  # Process already exited

        # # Register signals to forward
        # signals_to_forward = [signal.SIGINT, signal.SIGTERM]
        # if hasattr(signal, "SIGHUP"):
        #     signals_to_forward.append(signal.SIGHUP)
        # for sig in signals_to_forward:
        #     signal.signal(sig, forward_signal)

        # Open log file for writing
        assert process.stdout is not None
        with open(logfile, "w", buffering=1) as log_file:
            for line in process.stdout:
                from datetime import datetime
                timestamped = f"{datetime.now().strftime('%Y-%m-%d-%H:%M:%S.%f')} {line}"
                print(timestamped, end='')       # Print to terminal
                log_file.write(timestamped)      # Write to file

        process.wait()
        sys.exit(process.returncode)

    # This is the second run: continue with actual logic
    # (We return to do that)
