from threading import Thread, Event
import time
import os
import signal


class LEDState:
    def __init__(self, led_path: str, led_trigger_path: str, indicate: bool):
        self.led_path = led_path
        self.led_trigger_path = led_trigger_path
        self.indicate = indicate
        self._blink_thread = None
        self._stop_event = Event()
        self._trap_installed = False
        self.reset_led = lambda: None

    # =========================
    # LED Control
    # =========================

    def write_led(self, value: str):
        try:
            with open(self.led_path, "w") as f:
                f.write(value)
        except Exception as e:
            print(f"[LEDState] Failed to write to LED: {e}")

    def reset_to_default(self):
        if self.indicate:
            try:
                with open(self.led_trigger_path, "w") as f:
                    f.write("mmc0")
                print("[LEDState] Reset LED to default (mmc0)")
            except Exception as e:
                print(f"[LEDState] Failed to reset LED trigger: {e}")

    # def install_trap(self):
    #     if not self._trap_installed:
    #         def handle_exit(signum, frame):
    #             print("[LEDState] Caught exit signal, resetting LED...")
    #             self.stop_blinking()
    #             self.reset_to_default()
    #             os._exit(0)  # Ensure we actually exit

    #         signal.signal(signal.SIGTERM, handle_exit)
    #         signal.signal(signal.SIGINT, handle_exit)
    #         self._trap_installed = True

    # =========================
    # LED Mode Changing
    # =========================

    # `delay` is in seconds.
    def start_blinking(self, delay=0.5):
        if not self.indicate or self._blink_thread:
            return

        self._stop_event.clear()

        def blink():
            print("[LEDState] Starting LED blink loop.")
            while not self._stop_event.is_set():
                self.write_led("0")
                time.sleep(delay)
                self.write_led("1")
                time.sleep(delay)
            print("[LEDState] Exiting LED blink loop.")

        self._blink_thread = Thread(target=blink, daemon=True)
        self._blink_thread.start()
        #self.install_trap()

    def stop_blinking(self):
        if self._blink_thread:
            print("[LEDState] Stopping LED blinking thread.")
            self._stop_event.set()
            self._blink_thread.join()
            self._blink_thread = None

    def solid_on(self):
        if self.indicate:
            self.stop_blinking()
            self.write_led("1")
            #self.install_trap()

    def solid_off(self):
        if self.indicate:
            self.stop_blinking()
            self.write_led("0")
            #self.install_trap()
