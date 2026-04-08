from pynput import keyboard
import websocket
import cv2
import time
import sys
import os
import threading
import numpy as np

# ── ESP32 WebSocket ──────────────────────────────────────────────────────────
ESP32_IP   = "192.168.4.1"
ESP32_PORT = 81

SPEED = 1620

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
    keyboard.Key.up:    (1650, 1500, "UP"),
    keyboard.Key.down:  (1450, 1500, "DOWN"),
    keyboard.Key.right: (1600, 1700, "RIGHT"),
    keyboard.Key.left:  (1600, 1300, "LEFT"),
}

IDLE = (1500, 1500, "IDLE")

current_state = IDLE
latched_state = IDLE
ws_conn = None

# ── Camera / ArUco config ────────────────────────────────────────────────────
CAMERA_INDEX = 1
TRACK_TAG_ID = None  # None = track first detected tag; set to int for a specific ID

# ── Recording ────────────────────────────────────────────────────────────────
RAWDATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rawdata")
recording = False
record_t0 = 0.0  # set via time.perf_counter() when recording starts
current_rot = None
record_data = []
record_lock = threading.Lock()

x = np.nan
y = np.nan
tracker_lock = threading.Lock()


# ── ArUco tracker thread ────────────────────────────────────────────────────
def tracker_loop():
    """Background thread: reads camera, detects ArUco markers, updates x/y."""
    global x, y

    cam = cv2.VideoCapture(CAMERA_INDEX)
    cam.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
    cam.set(cv2.CAP_PROP_FRAME_WIDTH, 3840)
    cam.set(cv2.CAP_PROP_FRAME_HEIGHT, 2160)
    w = cam.get(cv2.CAP_PROP_FRAME_WIDTH)
    h = cam.get(cv2.CAP_PROP_FRAME_HEIGHT)
    print(f"[TRACKER] Camera opened: {int(w)}x{int(h)}")

    aruco_dict = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_6X6_250)
    aruco_parameters = cv2.aruco.DetectorParameters()
    detector = cv2.aruco.ArucoDetector(aruco_dict, aruco_parameters)

    tag_size = 0.075  # metres
    fname = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         'calibration_chessboard_4k_tank.yaml')
    fs = cv2.FileStorage(fname, cv2.FILE_STORAGE_READ)
    if not fs.isOpened():
        raise RuntimeError(f"Failed to open {fname}")
    K = fs.getNode("K").mat()
    D = fs.getNode("D").mat()
    fs.release()
    camera_matrix = np.asarray(K, dtype=float)
    dist_coeffs = np.asarray(D, dtype=float).reshape(-1)

    prev_tags = {}

    cv2.namedWindow('Tracker', cv2.WINDOW_NORMAL)
    cv2.resizeWindow('Tracker', 960, 540)

    print("[TRACKER] Tracking started – press ESC in remote to quit")

    while True:
        ret, image = cam.read()
        if not ret:
            continue

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        corners, ids, _ = detector.detectMarkers(gray)

        if ids is not None:
            center_pixel = []
            for c in range(len(corners)):
                for corner in corners[c]:
                    cx = int(np.mean(corner[:, 0]))
                    cy = int(np.mean(corner[:, 1]))
                    center_pixel.append((cx, cy))

            rvecs, tvecs, _ = cv2.aruco.estimatePoseSingleMarkers(
                corners, tag_size, camera_matrix, dist_coeffs)

            for i, tag_id in enumerate(ids.flatten()):
                rvec = rvecs[i]
                tvec = tvecs[i]

                cv2.drawFrameAxes(image, camera_matrix, dist_coeffs, rvec, tvec, 0.1)
                cv2.circle(image, center_pixel[i], 5, (0, 255, 0), -1)

                if tag_id in prev_tags:
                    for c in range(50):
                        idx = len(prev_tags[tag_id]) - 1 - c
                        if idx < 0:
                            break
                        cv2.line(image, prev_tags[tag_id][idx][0],
                                 prev_tags[tag_id][idx - 1][0], (0, 255, 0), 2)
                    prev_tags[tag_id].append([center_pixel[i], rvec, tvec])
                else:
                    prev_tags[tag_id] = [[center_pixel[i], rvec, tvec]]

                if TRACK_TAG_ID is None or tag_id == TRACK_TAG_ID:
                    with tracker_lock:
                        x = tvec[0][0]
                        y = tvec[0][1]

        cv2.imshow('Tracker', image)
        cv2.waitKey(1)


# ── Recorder thread ─────────────────────────────────────────────────────────
def recorder_loop():
    """Background thread that samples data at 30 Hz while recording."""
    while True:
        time.sleep(1 / 30)
        with record_lock:
            if recording:
                prop, rud, _ = current_state
                with tracker_lock:
                    cur_x, cur_y = x, y
                record_data.append([round(time.perf_counter() - record_t0, 3),
                                    cur_x, cur_y, prop, rud])


# ── WebSocket / command helpers ──────────────────────────────────────────────
def send_command(propeller, rudder):
    msg = f"P{propeller},R{rudder}"
    try:
        ws_conn.send(msg)
    except Exception as e:
        print(f"[WS ERROR] {e}")


def apply_state(state):
    global current_state
    if state != current_state:
        current_state = state
        prop, rud, label = state
        send_command(prop, rud)
        with tracker_lock:
            cur_x, cur_y = x, y
        print(f"[{time.time():.3f}] propeller={prop}  rudder={rud}  "
              f"({label})  x={cur_x}  y={cur_y}")


# ── Keyboard handlers ───────────────────────────────────────────────────────
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
    if key in ARROW_PRESETS:
        apply_state(latched_state)


# ── Utility ──────────────────────────────────────────────────────────────────
def get_next_trial(rot_num):
    os.makedirs(RAWDATA_DIR, exist_ok=True)
    trial = 1
    while os.path.exists(os.path.join(RAWDATA_DIR, f"rot{rot_num}_trial{trial}.csv")):
        trial += 1
    return trial


# ── Main ─────────────────────────────────────────────────────────────────────
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
    print("=== Boat Remote + Live ArUco Tracking ===")
    print(f"Speed (propeller) fixed at {SPEED} for number keys")
    print("Arrow keys: UP/DOWN = throttle, LEFT/RIGHT = steer")
    print("Number keys 1-5: preset rudder angles [1650..1850] (latched) + set rotation")
    print("F = forward (2000), R = reverse (1000), N = neutral (1500) (latched)")
    print("S = start recording, E = save recording, X = discard recording")
    print(f"Data saved to: {RAWDATA_DIR}")
    print("ESC to quit\n")

    threading.Thread(target=tracker_loop, daemon=True).start()
    threading.Thread(target=recorder_loop, daemon=True).start()

    try:
        with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
            listener.join()
    finally:
        ws_conn.close()
        print("WebSocket closed.")


if __name__ == "__main__":
    main()
