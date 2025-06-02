import os
import subprocess
import getpass
import sys

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
    import tempfile
    with tempfile.NamedTemporaryFile("w", delete=False) as tf:
        tf.writelines(updated_lines)
        tempname = tf.name

    # Validate the temp file syntax
    # cmd = ["visudo", "-cf", tempname]
    # proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    cmd = ["sudo", "visudo", "-cf", tempname]
    proc = subprocess.run(cmd, stdin=sys.stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        print(f"Syntax error in sudoers file:\n{proc.stderr}")
        os.unlink(tempname)
        raise RuntimeError("Invalid sudoers syntax; aborting.")

    # Move temp file to sudoers.d (requires root)
    os.rename(tempname, sudoers_file)
    os.chmod(sudoers_file, 0o440)
    print(f"Rule added to {sudoers_file} successfully.")
