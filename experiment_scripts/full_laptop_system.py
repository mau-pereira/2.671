from datetime import datetime
import os
import sys
import threading
import time

import cv2
import numpy as np
from pynput import keyboard
import websocket

from test_trajectory_read import (
    CAMERA_INDEX,
    CAMERA_FPS,
    FRAME_HEIGHT,
    FRAME_WIDTH,
    MANUAL_EXPOSURE,
    MANUAL_GAIN,
    TARGET_TAG_ID,
)
# from test_trajectory_read import create_trajectory_tracker, get_marker_xy_world_from_frame
# from test_yaw_read import create_yaw_tracker, get_marker_yaw_world_from_frame
from setup import make_frequency_checker


# -- ESP32 WebSocket -----------------------------------------------------------
ESP32_IP = "192.168.4.1"
ESP32_PORT = 81

# -- Runtime sampling ----------------------------------------------------------
RECORD_HZ = 60.0
SHOW_CAMERA_FEED = False
SHOW_FREQUENCY_CHECK = False
RAWDATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rawdata")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INTRINSICS_PATH = os.path.join(
    SCRIPT_DIR,
    "calibration",
    "calibration_images_april21",
    "calibration_intrinsics_april21.yaml",
)
EXTRINSICS_PATH = os.path.join(
    SCRIPT_DIR,
    "calibration",
    "calibration_extrinsics_april21.yaml",
)
ARUCO_DICT = cv2.aruco.DICT_6X6_250
WORLD_PLANE_Z = 0.0

# -- Shared state --------------------------------------------------------------
ws_conn = None
running = True

tracker_lock = threading.Lock()
x_world = np.nan
y_world = np.nan
yaw_world = np.nan

state_lock = threading.Lock()
current_propeller_pwm = 1500
current_rudder_pwm = 1500

record_lock = threading.Lock()
recording = False
record_t0 = 0.0
record_data = []
trajectory_thread = None


def load_intrinsics(path: str):
    fs = cv2.FileStorage(path, cv2.FILE_STORAGE_READ)
    if not fs.isOpened():
        raise RuntimeError(f"Failed to open intrinsics file: {path}")
    k = fs.getNode("K").mat()
    d = fs.getNode("D").mat()
    fs.release()
    if k is None or d is None:
        raise RuntimeError("Intrinsics file missing K or D.")
    return np.asarray(k, dtype=float), np.asarray(d, dtype=float).reshape(-1)


def load_extrinsics(path: str):
    fs = cv2.FileStorage(path, cv2.FILE_STORAGE_READ)
    if not fs.isOpened():
        raise RuntimeError(f"Failed to open extrinsics file: {path}")
    rvec = fs.getNode("rvec_world_to_cam").mat()
    tvec = fs.getNode("tvec_world_to_cam").mat()
    fs.release()
    if rvec is None or tvec is None:
        raise RuntimeError("Extrinsics file missing rvec_world_to_cam or tvec_world_to_cam.")
    return np.asarray(rvec, dtype=float).reshape(3, 1), np.asarray(tvec, dtype=float).reshape(3, 1)


def pixel_to_world_plane_fast(
    u: float,
    v: float,
    k: np.ndarray,
    d: np.ndarray,
    r_cw: np.ndarray,
    cam_origin_world: np.ndarray,
    world_z: float,
) -> np.ndarray:
    pts = np.array([[[u, v]]], dtype=np.float64)
    undist = cv2.undistortPoints(pts, k, d)
    ray_cam = np.array([undist[0, 0, 0], undist[0, 0, 1], 1.0], dtype=float)
    ray_world = r_cw @ ray_cam
    if abs(ray_world[2]) < 1e-12:
        return np.array([np.nan, np.nan, world_z], dtype=float)
    t_param = (world_z - cam_origin_world[2]) / ray_world[2]
    return cam_origin_world + t_param * ray_world


def get_marker_state_world_from_frame(
    image: np.ndarray,
    detector: cv2.aruco.ArucoDetector,
    target_tag_id: int,
    k: np.ndarray,
    d: np.ndarray,
    r_cw: np.ndarray,
    cam_origin_world: np.ndarray,
    world_plane_z: float = WORLD_PLANE_Z,
):
    """
    Single-pass ArUco processing for x, y, yaw from one frame.
    Returns None when the target marker is not detected.
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    corners, ids, _ = detector.detectMarkers(gray)
    if ids is None:
        return None

    ids_flat = ids.flatten()
    hit = np.where(ids_flat == target_tag_id)[0]
    if hit.size == 0:
        return None

    i = int(hit[0])
    crn = corners[i].reshape(4, 2)  # TL, TR, BR, BL
    cx = float(np.mean(crn[:, 0]))
    cy = float(np.mean(crn[:, 1]))

    p_center = pixel_to_world_plane_fast(cx, cy, k, d, r_cw, cam_origin_world, world_plane_z)
    p_tl = pixel_to_world_plane_fast(float(crn[0, 0]), float(crn[0, 1]), k, d, r_cw, cam_origin_world, world_plane_z)
    p_tr = pixel_to_world_plane_fast(float(crn[1, 0]), float(crn[1, 1]), k, d, r_cw, cam_origin_world, world_plane_z)

    if not (np.isfinite(p_center[0]) and np.isfinite(p_center[1]) and np.isfinite(p_tl[0]) and np.isfinite(p_tr[0])):
        return None

    yaw_rad = np.arctan2(p_tr[1] - p_tl[1], p_tr[0] - p_tl[0])
    return float(p_center[0]), float(p_center[1]), float(yaw_rad)


def build_trajectory():
    """
    TODO: Build the trajectory your boat should follow.

    Return a list of segments:
        (duration_s, u_propeller_pwm, u_rudder_pwm, label)
    """
    return []


def send_command(propeller_pwm: int, rudder_pwm: int):
    """Low-level WebSocket send only."""
    msg = f"P{propeller_pwm},R{rudder_pwm}"
    try:
        ws_conn.send(msg)
    except Exception as exc:
        print(f"[WS ERROR] {exc}")


def apply_command(propeller_pwm: int, rudder_pwm: int, label: str):
    """Update local command state, then send/log if it changed."""
    global current_propeller_pwm, current_rudder_pwm
    with state_lock:
        changed = (
            propeller_pwm != current_propeller_pwm
            or rudder_pwm != current_rudder_pwm
        )
        current_propeller_pwm = int(propeller_pwm)
        current_rudder_pwm = int(rudder_pwm)

    if changed:
        send_command(int(propeller_pwm), int(rudder_pwm))
        with tracker_lock:
            cur_x = x_world
            cur_y = y_world
            cur_yaw = yaw_world
        print(
            f"[{time.time():.3f}] {label}: "
            f"u_propeller={int(propeller_pwm)} u_rudder={int(rudder_pwm)} "
            f"x={cur_x} y={cur_y} yaw={cur_yaw}"
        )


def start_recording():
    global recording, record_t0, record_data
    with record_lock:
        if recording:
            print("Already recording.")
            return False
        record_data = []
        record_t0 = time.perf_counter()
        recording = True
    print("[0.000] >>> RECORDING STARTED")
    return True


def save_recording():
    global recording, record_data
    with record_lock:
        if not recording:
            print("Not recording.")
            return
        recording = False
        n = len(record_data)
        payload = np.array(record_data, dtype=float) if n > 0 else np.empty((0, 6))
        record_data = []

    os.makedirs(RAWDATA_DIR, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    fname = os.path.join(RAWDATA_DIR, f"trajectory_capture_{stamp}.csv")
    np.savetxt(
        fname,
        payload,
        delimiter=",",
        header="timestamp,u_propeller_pwm,u_rudder_pwm,x,y,yaw",
        comments="",
    )
    print(f">>> SAVED {n} samples -> {fname}")


def discard_recording():
    global recording, record_data
    with record_lock:
        if not recording:
            print("Not recording.")
            return
        n = len(record_data)
        recording = False
        record_data = []
    print(f">>> DISCARDED {n} samples")


def tracker_loop():
    """Read camera frames and continuously update shared x, y, yaw."""
    global x_world, y_world, yaw_world, running

    k, d = load_intrinsics(INTRINSICS_PATH)
    rvec_w2c, tvec_w2c = load_extrinsics(EXTRINSICS_PATH)
    r_wc, _ = cv2.Rodrigues(rvec_w2c)
    r_cw = r_wc.T
    cam_origin_world = -r_cw @ tvec_w2c.reshape(3)
    aruco_dict = cv2.aruco.getPredefinedDictionary(ARUCO_DICT)
    detector = cv2.aruco.ArucoDetector(aruco_dict, cv2.aruco.DetectorParameters())
    freq_tick = make_frequency_checker(label="tracker_loop", print_every_s=2.0) if SHOW_FREQUENCY_CHECK else None

    cam = cv2.VideoCapture(CAMERA_INDEX)
    cam.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cam.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cam.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    cam.set(cv2.CAP_PROP_FPS, CAMERA_FPS)
    cam.set(cv2.CAP_PROP_AUTO_EXPOSURE, 1)
    cam.set(cv2.CAP_PROP_EXPOSURE, MANUAL_EXPOSURE)
    cam.set(cv2.CAP_PROP_GAIN, MANUAL_GAIN)

    if not cam.isOpened():
        print(f"[TRACKER] Failed to open camera index {CAMERA_INDEX}")
        running = False
        return

    if SHOW_CAMERA_FEED:
        cv2.namedWindow("Tracker", cv2.WINDOW_NORMAL)
        cv2.resizeWindow("Tracker", 1280, 720)
    print(f"[TRACKER] Tracking tag id {TARGET_TAG_ID}.")

    while running:
        ret, image = cam.read()
        if not ret:
            continue
        if freq_tick is not None:
            freq_tick()

        state = get_marker_state_world_from_frame(
            image=image,
            detector=detector,
            target_tag_id=TARGET_TAG_ID,
            k=k,
            d=d,
            r_cw=r_cw,
            cam_origin_world=cam_origin_world,
        )

        with tracker_lock:
            if state is not None:
                x_world, y_world, yaw_world = state
            else:
                x_world, y_world = np.nan, np.nan
                yaw_world = np.nan
            cur_x = x_world
            cur_y = y_world
            cur_yaw = yaw_world

        if SHOW_CAMERA_FEED:
            draw = image.copy()
            text = f"x={cur_x:.3f} y={cur_y:.3f} yaw={cur_yaw:.3f} rad"
            cv2.putText(
                draw,
                text,
                (16, 32),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (0, 255, 0) if np.isfinite(cur_x) else (0, 0, 255),
                2,
                cv2.LINE_AA,
            )
            cv2.imshow("Tracker", draw)
            cv2.waitKey(1)

    cam.release()
    if SHOW_CAMERA_FEED:
        cv2.destroyWindow("Tracker")


def recorder_loop():
    """Sample command + state at RECORD_HZ while recording is enabled."""
    global record_data
    dt = 1.0 / RECORD_HZ
    while running:
        time.sleep(dt)
        with record_lock:
            if not recording:
                continue
            t_rel = round(time.perf_counter() - record_t0, 3)
            with state_lock:
                u_prop = current_propeller_pwm
                u_rud = current_rudder_pwm
            with tracker_lock:
                cur_x = x_world
                cur_y = y_world
                cur_yaw = yaw_world
            record_data.append([t_rel, u_prop, u_rud, cur_x, cur_y, cur_yaw])


def trajectory_runner():
    """Execute trajectory segments and return boat to neutral at the end."""
    segments = build_trajectory()
    if not segments:
        print("Trajectory is empty. Using one fallback segment so boat still moves.")
        segments = [(1.5, 1600, 1500, "AUTO_START_FALLBACK")]

    for duration_s, u_prop, u_rud, label in segments:
        if not running:
            break
        apply_command(int(u_prop), int(u_rud), str(label))
        t_start = time.perf_counter()
        while running and (time.perf_counter() - t_start) < float(duration_s):
            time.sleep(0.01)

    apply_command(1500, 1500, "TRAJECTORY_DONE_IDLE")
    print("Trajectory complete.")


def start_trajectory_and_record():
    """One-shot start for recording plus background trajectory execution."""
    global trajectory_thread
    if trajectory_thread is not None and trajectory_thread.is_alive():
        print("Trajectory is already running.")
        return
    if not start_recording():
        return
    trajectory_thread = threading.Thread(target=trajectory_runner, daemon=True)
    trajectory_thread.start()


def on_press(key):
    try:
        ch = key.char
    except AttributeError:
        ch = None

    if ch == "t":
        start_trajectory_and_record()
        return
    if ch == "s":
        start_recording()
        return
    if ch == "e":
        save_recording()
        return
    if ch == "x":
        discard_recording()
        return
    if ch == "n":
        apply_command(1500, 1500, "MANUAL_NEUTRAL")
        return
    if ch == "f":
        apply_command(1700, 1500, "MANUAL_FORWARD")
        return
    if ch == "r":
        apply_command(1200, 1500, "MANUAL_REVERSE")
        return

    if key == keyboard.Key.left:
        apply_command(current_propeller_pwm, 1200, "MANUAL_LEFT")
    elif key == keyboard.Key.right:
        apply_command(current_propeller_pwm, 1800, "MANUAL_RIGHT")
    elif key == keyboard.Key.up:
        apply_command(1675, current_rudder_pwm, "MANUAL_THROTTLE_UP")
    elif key == keyboard.Key.down:
        apply_command(1100, current_rudder_pwm, "MANUAL_THROTTLE_DOWN")


def on_release(key):
    global running
    if key == keyboard.Key.esc:
        running = False
        apply_command(1500, 1500, "EXIT_IDLE")
        print("ESC pressed. Exiting.")
        return False
    if key in {keyboard.Key.left, keyboard.Key.right}:
        apply_command(current_propeller_pwm, 1500, "RUDDER_CENTER")


def main():
    global ws_conn, running
    url = f"ws://{ESP32_IP}:{ESP32_PORT}"
    print(f"Connecting to ESP32 at {url} ...")

    try:
        ws_conn = websocket.create_connection(url, timeout=5)
    except Exception as exc:
        print(f"Could not connect: {exc}")
        print("Make sure you're connected to the AccessPoint_ESP32 WiFi network.")
        sys.exit(1)

    print("Connected!\n")
    print("=== Full Laptop System (Modular Vision) ===")
    # print(f"Tracking source: test_trajectory_read.py + test_yaw_read.py")
    # print(f"Camera index/resolution settings from trajectory/yaw scripts.")
    print("T = start trajectory + data capture")
    print("S = start data capture (manual driving)")
    print("E = save recording, X = discard recording")
    print("F/R/N + arrows for manual override")
    print("ESC to quit")
    print(f"Data saved to: {RAWDATA_DIR}\n")

    tracker = threading.Thread(target=tracker_loop, daemon=True)
    recorder = threading.Thread(target=recorder_loop, daemon=True)
    tracker.start()
    recorder.start()

    try:
        with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
            listener.join()
    finally:
        running = False
        try:
            apply_command(1500, 1500, "FINAL_IDLE")
        except Exception:
            pass
        if ws_conn is not None:
            ws_conn.close()
        print("WebSocket closed.")


if __name__ == "__main__":
    main()
