import os
import subprocess
import getpass
import sys
import tempfile

def move_and_chmod_with_sudo(tempname, sudoers_file):
    # Change owner with sudo
    chown_cmd = ["sudo", "chown", "root", tempname]
    proc_chown = subprocess.run(chown_cmd, stdin=sys.stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc_chown.returncode != 0:
        raise RuntimeError(f"Failed to chown file with sudo:\n{proc_chown.stderr}")

    # Move file with sudo
    mv_cmd = ["sudo", "mv", tempname, sudoers_file]
    proc_mv = subprocess.run(mv_cmd, stdin=sys.stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc_mv.returncode != 0:
        raise RuntimeError(f"Failed to move file with sudo:\n{proc_mv.stderr}")

    # Change mode with sudo
    chmod_cmd = ["sudo", "chmod", "440", sudoers_file]
    proc_chmod = subprocess.run(chmod_cmd, stdin=sys.stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc_chmod.returncode != 0:
        raise RuntimeError(f"Failed to chmod file with sudo:\n{proc_chmod.stderr}")

def add_sudoers_rule(command: str, username: str|None = None):
    """
    Add a sudoers rule to allow 'username' to run the exact 'command' without password.
    Creates/updates /etc/sudoers.d/username file safely.

    Args:
        command (str): Full command with absolute path and arguments, e.g. "/bin/chown alice /path/to/file"
        username (str): User to whom to grant permission. Defaults to current user.
    """

    if username is None:
        username = getpass.getuser()

    sudoers_dir = "/etc/sudoers.d"
    sudoers_file = os.path.join(sudoers_dir, username)

    line = f"{username} ALL=(ALL) NOPASSWD: {command}\n"

    # Read existing lines if file exists
    existing_lines = []
    if os.path.exists(sudoers_file):
        with open(sudoers_file, "r") as f:
            existing_lines = f.readlines()

    # Check if line already present
    if any(line.strip() == l.strip() for l in existing_lines):
        print(f"Rule already present for user {username}. No changes made.")
        return

    # Append the rule
    updated_lines = existing_lines + [line]

    # Write to temp file first
    with tempfile.NamedTemporaryFile("w", delete=False) as tf:
        tf.writelines(updated_lines)
        tempname = tf.name

        try:
            # Validate the temp file syntax
            # cmd = ["visudo", "-cf", tempname]
            # proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            cmd = ["sudo", "visudo", "-cf", tempname]
            proc = subprocess.run(cmd, stdin=sys.stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            print(proc.returncode)
            import pdb
            pdb.set_trace()
            if proc.returncode != 0:
                print(f"Syntax error in sudoers file:\n{proc.stderr}")
                os.unlink(tempname)
                raise RuntimeError("Invalid sudoers syntax; aborting.")

            ## Move temp file to sudoers.d (requires root)
            # os.rename(tempname, sudoers_file)
            # os.chmod(sudoers_file, 0o440)

            # Move temp file to sudoers.d (uses sudo)
            move_and_chmod_with_sudo(tempname, sudoers_file)
            print(f"Rule added to {sudoers_file} successfully.")
        except:
            # Delete tempfile on failure
            if os.path.exists(tempname):
                os.unlink(tempname)
            raise
