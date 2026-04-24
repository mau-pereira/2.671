from pynput import keyboard
import websocket
import time
import sys
import os
import threading
import numpy as np

ESP32_IP   = "192.168.4.1"
ESP32_PORT = 81

SPEED = 1600

LATCH_PRESETS = {
    '1': (SPEED, 1650, "RUDDER 1"),
    '2': (SPEED, 1700, "RUDDER 2"),
    '3': (SPEED, 1750, "RUDDER 3"),
    '4': (SPEED, 1800, "RUDDER 4"),
    '5': (SPEED, 1850, "RUDDER 5"),
    'f': (2000, 1500, "FORWARD"),
    'r': (1000, 1500, "REVERSE"),
    'n': (1500, 1500, "NEUTRAL"),
}

ARROW_PRESETS = {
    keyboard.Key.up:    (1600, 1500, "UP"),
    keyboard.Key.down:  (1400, 1500, "DOWN"),
    keyboard.Key.right: (1600, 2000, "RIGHT"),
    keyboard.Key.left:  (1600, 1000, "LEFT"),
}

IDLE = (1500, 1500, "IDLE")

current_state = IDLE
latched_state = IDLE
ws_conn = None

# --- Recording ---
RAWDATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rawdata")
x, y = 9, 9
recording = False
record_t0 = 0.0  # set via time.perf_counter() when recording starts
current_rot = None
record_data = []
record_lock = threading.Lock()


def get_next_trial(rot_num):
    """Find the next available trial number for a given rotation."""
    os.makedirs(RAWDATA_DIR, exist_ok=True)
    trial = 1
    while os.path.exists(os.path.join(RAWDATA_DIR, f"rot{rot_num}_trial{trial}.csv")):
        trial += 1
    return trial


def recorder_loop():
    """Background thread that samples data at 30 Hz while recording."""
    while True:
        time.sleep(1 / 30)
        with record_lock:
            if recording:
                prop, rud, _ = current_state
                record_data.append([round(time.perf_counter() - record_t0, 3),
                                    x, y, prop, rud])


def send_command(propeller, rudder):
    """Send a P<val>,R<val> message to the ESP32."""
    msg = f"P{propeller},R{rudder}"
    try:
        ws_conn.send(msg)
    except Exception as e:
        print(f"[WS ERROR] {e}")


def apply_state(state):
    """Update current state, send command, and print."""
    global current_state
    if state != current_state:
        current_state = state
        prop, rud, label = state
        send_command(prop, rud)
        print(f"[{time.time():.3f}] propeller={prop}  rudder={rud}  ({label})")


def on_press(key):
    global latched_state, recording, record_t0, record_data, current_rot

    try:
        ch = key.char
    except AttributeError:
        ch = None

    if ch == 's':
        with record_lock:
            if recording:
                print("Already recording!")
                return
            if current_rot is None:
                print("Select a rotation first (1-5)!")
                return
            record_data = []
            record_t0 = time.perf_counter()
            recording = True
        print(f"[0.000] >>> RECORDING STARTED (rot{current_rot})")
        return

    if ch == 'e':
        with record_lock:
            if not recording:
                print("Not recording.")
                return
            recording = False
            trial = get_next_trial(current_rot)
            fname = os.path.join(RAWDATA_DIR, f"rot{current_rot}_trial{trial}.csv")
            data = np.array(record_data)
            np.savetxt(fname, data, delimiter=',',
                       header='timestamp,x,y,pwm_prop,pwm_rudder', comments='')
            n = len(record_data)
            record_data = []
        print(f"[{time.time():.3f}] >>> SAVED {n} samples -> {fname}")
        return

    if ch == 'x':
        with record_lock:
            if not recording:
                print("Not recording.")
                return
            recording = False
            n = len(record_data)
            record_data = []
        print(f"[{time.time():.3f}] >>> DISCARDED {n} samples")
        return

    if ch and ch in LATCH_PRESETS:
        if ch in '12345':
            current_rot = int(ch)
        latched_state = LATCH_PRESETS[ch]
        apply_state(latched_state)
        return

    state = ARROW_PRESETS.get(key)
    if state:
        latched_state = IDLE
        apply_state(state)


def on_release(key):
    if key == keyboard.Key.esc:
        send_command(1500, 1500)
        print("Sending IDLE and exiting...")
        return False
    # Arrow released: return to latched preset (or IDLE)
    if key in ARROW_PRESETS:
        apply_state(latched_state)


def main():
    global ws_conn

    url = f"ws://{ESP32_IP}:{ESP32_PORT}"
    print(f"Connecting to ESP32 at {url} ...")

    try:
        ws_conn = websocket.create_connection(url, timeout=5)
    except Exception as e:
        print(f"Could not connect: {e}")
        print("Make sure you're connected to the AccessPoint_ESP32 WiFi network.")
        sys.exit(1)

    print("Connected!\n")
    print("=== Boat Remote Control (WebSocket) ===")
    print(f"Speed (propeller) fixed at {SPEED} for number keys")
    print("Arrow keys: UP/DOWN = throttle, LEFT/RIGHT = steer")
    print("Number keys 1-5: preset rudder angles [1650..1850] (latched) + set rotation")
    print("F = forward (2000), R = reverse (1000), N = neutral (1500) (latched)")
    print("S = start recording, E = save recording, X = discard recording")
    print(f"Data saved to: {RAWDATA_DIR}")
    print("ESC to quit\n")

    rec_thread = threading.Thread(target=recorder_loop, daemon=True)
    rec_thread.start()

    try:
        with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
            listener.join()
    finally:
        ws_conn.close()
        print("WebSocket closed.")


if __name__ == "__main__":
    main()
