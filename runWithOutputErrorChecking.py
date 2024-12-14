import subprocess
import re
import sys

def hasError(line):
    # The regex pattern to search for
    ERROR_PATTERN = r"ftpfs: operation ftpfs_getattr failed because No such file or directory"
    hasError = re.search(ERROR_PATTERN, line)

    return hasError

def run_command_and_check_output(command):
    try:
        # Run the command as a subprocess
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,  # Ensures output is in string format
            #shell=True  # Allows command to be passed as a single string
        )

        # Check stdout and stderr line-by-line
        for line in process.stdout:
            print(line, end="")  # Print the output as it happens
            if hasError(line):
                print(f"Error pattern found in stdout: {line.strip()}")
                process.terminate()  # Stop the process if match is found
                sys.exit(1)

        for line in process.stderr:
            print(line, end="")  # Print the error output as it happens
            if hasError(line):
                print(f"Error pattern found in stderr: {line.strip()}")
                process.terminate()  # Stop the process if match is found
                sys.exit(1)

        # Wait for the process to complete
        process.wait()

        # Exit with the command's exit code
        sys.exit(process.returncode)

    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"An error occurred: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:", sys.argv[0], "<command>")
        sys.exit(1)

    command_to_run = sys.argv[1:]
    #print(command_to_run)
    run_command_and_check_output(command_to_run)
