#!/usr/bin/env python
"""
Read one ArUco marker trajectory in world coordinates using saved calibration.
"""

import os
import threading
import time

import cv2
import matplotlib.pyplot as plt
import numpy as np


# -----------------------------------------------------------------------------
# HARDCODED SETTINGS (edit these values only)
# -----------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

INTRINSICS_PATH = os.path.join(
    SCRIPT_DIR,
    "calibration",
    "calibration_images_may1",
    "calibration_intrinsics_may1.yaml",
)
EXTRINSICS_PATH = os.path.join(
    SCRIPT_DIR,
    "calibration",
    "calibration_extrinsics_may1.yaml",
)

CAMERA_INDEX = 1
ARUCO_DICT = cv2.aruco.DICT_6X6_250
TARGET_TAG_ID = 0
SAMPLE_HZ = 45
DURATION_S = 30

FRAME_WIDTH = 1440
FRAME_HEIGHT = 1080
CAMERA_FPS = 60
MANUAL_EXPOSURE = -6
MANUAL_GAIN = 0

WORLD_PLANE_Z = 0.0

# -- Optional boat remote control over ESP32 WebSocket -----------------------
# Set ENABLE_BOAT_CONTROL = True to drive the boat by keyboard while this
# script is also doing camera tracking. Mirrors the basic manual-control
# logic from full_laptop_system.py (no recording / trajectory engine).
ENABLE_BOAT_CONTROL = False
ESP32_IP = "192.168.4.1"
ESP32_PORT = 81
MANUAL_UP_PROP_PWM = 1650
MANUAL_RIGHT_RUDDER_PWM = 2000

# Module-level state used only when ENABLE_BOAT_CONTROL is True.
_ws_conn = None
_state_lock = threading.Lock()
_current_propeller_pwm = 1500
_current_rudder_pwm = 1500
_running = True


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


def create_trajectory_tracker(
    intrinsics_path: str = INTRINSICS_PATH,
    extrinsics_path: str = EXTRINSICS_PATH,
    aruco_dict_id: int = ARUCO_DICT,
):
    """Create reusable trajectory-tracker resources for external scripts."""
    k, d = load_intrinsics(intrinsics_path)
    rvec_w2c, tvec_w2c = load_extrinsics(extrinsics_path)
    r_wc, _ = cv2.Rodrigues(rvec_w2c)
    r_cw = r_wc.T
    cam_origin_world = -r_cw @ tvec_w2c.reshape(3)

    aruco_dict = cv2.aruco.getPredefinedDictionary(aruco_dict_id)
    detector = cv2.aruco.ArucoDetector(aruco_dict, cv2.aruco.DetectorParameters())

    return {
        "k": k,
        "d": d,
        "detector": detector,
        "r_cw": r_cw,
        "cam_origin_world": cam_origin_world,
    }


def get_marker_xy_world_from_frame(
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
    Return world-plane (x, y) for the marker center in one camera frame.
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
    crn = corners[i].reshape(4, 2)
    cx = float(np.mean(crn[:, 0]))
    cy = float(np.mean(crn[:, 1]))
    pw = pixel_to_world_plane_fast(cx, cy, k, d, r_cw, cam_origin_world, world_plane_z)

    if not np.isfinite(pw[0]) or not np.isfinite(pw[1]):
        return None

    return float(pw[0]), float(pw[1])


def _send_command(propeller_pwm: int, rudder_pwm: int):
    """Low-level WebSocket send. Mirrors full_laptop_system.send_command."""
    global _ws_conn
    if _ws_conn is None:
        return
    try:
        _ws_conn.send(f"P{int(propeller_pwm)},R{int(rudder_pwm)}")
    except Exception as exc:
        print(f"[WS ERROR] {exc}")


def _apply_command(propeller_pwm: int, rudder_pwm: int, label: str):
    """Update local command state, then send/log if it changed."""
    global _current_propeller_pwm, _current_rudder_pwm
    with _state_lock:
        changed = (
            propeller_pwm != _current_propeller_pwm
            or rudder_pwm != _current_rudder_pwm
        )
        _current_propeller_pwm = int(propeller_pwm)
        _current_rudder_pwm = int(rudder_pwm)
    if changed:
        _send_command(int(propeller_pwm), int(rudder_pwm))
        print(
            f"[{time.time():.3f}] {label}: "
            f"u_propeller={int(propeller_pwm)} u_rudder={int(rudder_pwm)}"
        )


def _make_key_handlers():
    """Build pynput on_press / on_release callbacks bound to module state."""
    from pynput import keyboard

    def on_press(key):
        global _running
        try:
            ch = key.char
        except AttributeError:
            ch = None

        if ch == "n":
            _apply_command(1500, 1500, "MANUAL_NEUTRAL")
            return
        if ch == "f":
            _apply_command(1700, 1500, "MANUAL_FORWARD")
            return
        if ch == "r":
            _apply_command(1200, 1500, "MANUAL_REVERSE")
            return

        if key == keyboard.Key.left:
            _apply_command(_current_propeller_pwm, 1000, "MANUAL_LEFT")
        elif key == keyboard.Key.right:
            _apply_command(_current_propeller_pwm, MANUAL_RIGHT_RUDDER_PWM, "MANUAL_RIGHT")
        elif key == keyboard.Key.up:
            _apply_command(MANUAL_UP_PROP_PWM, _current_rudder_pwm, "MANUAL_THROTTLE_UP")
        elif key == keyboard.Key.down:
            _apply_command(1300, _current_rudder_pwm, "MANUAL_THROTTLE_DOWN")

    def on_release(key):
        global _running
        if key == keyboard.Key.esc:
            _running = False
            _apply_command(1500, 1500, "EXIT_IDLE")
            print("ESC pressed. Exiting.")
            return False
        if key in {keyboard.Key.left, keyboard.Key.right}:
            _apply_command(_current_propeller_pwm, 1500, "RUDDER_CENTER")

    return on_press, on_release


def _start_boat_control():
    """Connect to ESP32 over WebSocket and start a non-blocking key listener.

    Returns (websocket_conn, listener) so caller can clean up on exit.
    Returns (None, None) and prints an error if the connection fails.
    """
    global _ws_conn
    import websocket
    from pynput import keyboard

    url = f"ws://{ESP32_IP}:{ESP32_PORT}"
    print(f"[BOAT] Connecting to ESP32 at {url} ...")
    try:
        _ws_conn = websocket.create_connection(url, timeout=5)
    except Exception as exc:
        print(f"[BOAT] Could not connect: {exc}")
        print("[BOAT] Make sure you're connected to the AccessPoint_ESP32 WiFi network.")
        _ws_conn = None
        return None, None

    print("[BOAT] Connected. Controls:")
    print("  Arrow Up/Down  : throttle up/down")
    print("  Arrow Left/Right: rudder left/right (auto-centers on key release)")
    print("  N/F/R          : neutral / forward / reverse")
    print("  ESC            : stop control (camera loop also exits)")

    on_press, on_release = _make_key_handlers()
    listener = keyboard.Listener(on_press=on_press, on_release=on_release)
    listener.start()
    return _ws_conn, listener


def _stop_boat_control(listener):
    """Send neutral, close WebSocket, and stop the keyboard listener."""
    global _ws_conn
    try:
        _apply_command(1500, 1500, "FINAL_IDLE")
    except Exception:
        pass
    if listener is not None:
        try:
            listener.stop()
        except Exception:
            pass
    if _ws_conn is not None:
        try:
            _ws_conn.close()
        except Exception:
            pass
        _ws_conn = None
    print("[BOAT] WebSocket closed.")


def main():
    k, d = load_intrinsics(INTRINSICS_PATH)
    rvec_w2c, tvec_w2c = load_extrinsics(EXTRINSICS_PATH)

    print(f"Intrinsics: {INTRINSICS_PATH}")
    print(f"Extrinsics: {EXTRINSICS_PATH}")
    print("Reminder: open Camo Studio for better detection rate / effective Hz.")
    camo_open = input("Is Camo Studio open? [Y/n]: ").strip().lower()
    if camo_open in {"n", "no"}:
        print("Warning: detections/Hz are worse if Camo Studio is not open.")
    print(f"Tracking ArUco id {TARGET_TAG_ID} for {DURATION_S} s (max-throughput mode).")

    aruco_dict = cv2.aruco.getPredefinedDictionary(ARUCO_DICT)
    detector = cv2.aruco.ArucoDetector(aruco_dict, cv2.aruco.DetectorParameters())
    r_wc, _ = cv2.Rodrigues(rvec_w2c)
    r_cw = r_wc.T
    cam_origin_world = -r_cw @ tvec_w2c.reshape(3)

    cam = cv2.VideoCapture(CAMERA_INDEX)
    cam.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cam.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cam.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    cam.set(cv2.CAP_PROP_FPS, CAMERA_FPS)
    if not cam.isOpened():
        raise RuntimeError(f"Failed to open camera index {CAMERA_INDEX}.")

    # Lock exposure so brightness does not drift during sampling.
    cam.set(cv2.CAP_PROP_AUTO_EXPOSURE, 1)
    cam.set(cv2.CAP_PROP_EXPOSURE, MANUAL_EXPOSURE)
    cam.set(cv2.CAP_PROP_GAIN, MANUAL_GAIN)

    listener = None
    if ENABLE_BOAT_CONTROL:
        _, listener = _start_boat_control()

    vision_x = []
    vision_y = []

    t0 = time.perf_counter()
    while True:
        t_rel = time.perf_counter() - t0
        if t_rel >= DURATION_S:
            break
        if not _running:
            break

        ret, image = cam.read()
        if not ret:
            continue

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        corners, ids, _ = detector.detectMarkers(gray)

        if ids is not None:
            ids_flat = ids.flatten()
            hit = np.where(ids_flat == TARGET_TAG_ID)[0]
            if hit.size > 0:
                i = int(hit[0])
                crn = corners[i].reshape(4, 2)
                cx = float(np.mean(crn[:, 0]))
                cy = float(np.mean(crn[:, 1]))

                pw = pixel_to_world_plane_fast(
                    cx,
                    cy,
                    k,
                    d,
                    r_cw,
                    cam_origin_world,
                    WORLD_PLANE_Z,
                )
                vision_x.append(float(pw[0]))
                vision_y.append(float(pw[1]))

    capture_elapsed_s = time.perf_counter() - t0
    cam.release()

    if ENABLE_BOAT_CONTROL:
        _stop_boat_control(listener)

    vision_x = np.asarray(vision_x, dtype=float)
    vision_y = np.asarray(vision_y, dtype=float)
    print(f"Capture loop wall time: {capture_elapsed_s:.3f} s (target {DURATION_S:.3f} s)")
    print(f"Vision detections: {vision_x.size}")

    fig, ax = plt.subplots(figsize=(7, 7))
    if vision_x.size > 0:
        ax.plot(vision_x, vision_y, "b.", markersize=4)
        ax.set_aspect("equal", adjustable="box")
    else:
        ax.text(
            0.5,
            0.5,
            "No valid trajectory samples detected",
            transform=ax.transAxes,
            ha="center",
            va="center",
            color="red",
        )

    ax.set_xlabel("x world (m)")
    ax.set_ylabel("y world (m)")
    ax.set_title(f"ArUco id {TARGET_TAG_ID}: x vs y (world)")
    ax.grid(True)
    fig.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
