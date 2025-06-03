import signal
import atexit
import traceback
import os
import sys
import threading

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

    # Exit as we normally would when getting this signal #
    # Restore the default handler for this signal
    signal.signal(signum, signal.SIG_DFL)
    
    # Re-raise the signal to perform the default action (exit)
    os.kill(os.getpid(), signum)
    # #

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

    if _led_state is not None and _led_state.indicate:
        print("[ibackupClient] Setting LED slow blink (every 1 second) in thread exception handler.")
        _led_state.start_blinking(1)

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

# Signal handler for SIGINT and SIGTERM
def handle_signal(signum, frame):
    global signal_termination_occurred
    signal_termination_occurred = True

    # Log the signal
    print(f"[ibackupClient] Received signal: {signum}. Exiting gracefully...")

    # Exit abruptly to skip atexit handlers (optional)
    # os._exit(0)

# Call this from outside this file.
def install_signal_handlers():
    signal.signal(signal.SIGINT, main_signal_handler)  # Handle Ctrl+C
    signal.signal(signal.SIGTERM, main_signal_handler)  # Handle termination signal

    # Set the custom exception hook for the main thread
    sys.excepthook = handle_unhandled_exception

    # Register the atexit handler
    atexit.register(on_exit)

    # Register signal handlers
    signal_handlers.append(handle_signal)

    return signal_handlers
