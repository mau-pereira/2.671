#!/usr/bin/env python
"""
Extrinsics-only calibration workflow for pool tracking.

This script runs only the extrinsics step from angled_calibration.py:
  - Load intrinsics
  - Capture fixed pool-plane ArUco markers
  - Solve world->camera extrinsics with solvePnP
  - Save extrinsics to calibration_extrinsics.yaml
"""

import os
from typing import Dict, List, Tuple

import cv2
import numpy as np


# -----------------------------------------------------------------------------
# Shared paths and constants
# -----------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# Set this once to choose which calibration dataset folder to load intrinsics from.
# This folder is expected under experiment_scripts/calibration/.
DATASET_FOLDER = os.path.join("calibration_images_may1")
INTRINSICS_FILENAME = "calibration_intrinsics_may1.yaml"
INTRINSICS_PATH = os.path.join(SCRIPT_DIR, DATASET_FOLDER, INTRINSICS_FILENAME)
CALIBRATION_EXTRINSICS_PATH = os.path.join(SCRIPT_DIR, "calibration_extrinsics.yaml")

ARUCO_DICT = cv2.aruco.DICT_6X6_250

# Pool layout: distances are entered in inches, stored in meters for OpenCV.
INCH_TO_M = 0.0254

# Physical marker printed square side (OpenCV / solvePnP use meters). 20 cm default.
DEFAULT_MARKER_SIZE_M = 0.2

# How many fixed pool markers define world frame for extrinsics.
EXTRINSICS_POOL_MARKER_COUNT = 4

# If True, uses EXTRINSICS_PRESET_MARKERS_INCHES (no typing). If False, prompts.
USE_EXTRINSICS_MARKER_PRESET = True
# Each row: (aruco_id, x_in, y_in, z_in) inches, flat pool plane (z=0).
EXTRINSICS_PRESET_MARKERS_INCHES = (
    (0, 0.0, 115.0, 0.0),
    (2, 0.0, 95.0, 0.0),
    (3, -110.0, 0.0, 0.0),
    (4, -45.0, 0.0, 0.0),
)


def rodrigues_from_euler_xyz(rx_deg: float, ry_deg: float, rz_deg: float) -> np.ndarray:
    """Euler XYZ degrees -> rvec (Rodrigues) for OpenCV transforms."""
    rx = np.deg2rad(rx_deg)
    ry = np.deg2rad(ry_deg)
    rz = np.deg2rad(rz_deg)
    cx, sx = np.cos(rx), np.sin(rx)
    cy, sy = np.cos(ry), np.sin(ry)
    cz, sz = np.cos(rz), np.sin(rz)

    rx_m = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]], dtype=float)
    ry_m = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]], dtype=float)
    rz_m = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]], dtype=float)
    rot = rz_m @ ry_m @ rx_m
    rvec, _ = cv2.Rodrigues(rot)
    return rvec.reshape(3, 1)


def board_marker_corners_world(
    center_xyz: Tuple[float, float, float],
    marker_size_m: float,
    yaw_deg: float = 0.0,
    pitch_deg: float = 0.0,
    roll_deg: float = 0.0,
) -> np.ndarray:
    """
    Returns 4 marker corner points in world frame.
    Corner order matches OpenCV ArUco corner order:
      top-left, top-right, bottom-right, bottom-left in marker local frame.
    """
    half = marker_size_m / 2.0
    corners_local = np.array(
        [
            [-half, +half, 0.0],  # top-left
            [+half, +half, 0.0],  # top-right
            [+half, -half, 0.0],  # bottom-right
            [-half, -half, 0.0],  # bottom-left
        ],
        dtype=float,
    )
    rvec = rodrigues_from_euler_xyz(roll_deg, pitch_deg, yaw_deg)
    rot, _ = cv2.Rodrigues(rvec)
    translated = (rot @ corners_local.T).T + np.array(center_xyz, dtype=float)
    return translated


def load_intrinsics(path: str) -> Tuple[np.ndarray, np.ndarray]:
    fs = cv2.FileStorage(path, cv2.FILE_STORAGE_READ)
    if not fs.isOpened():
        raise RuntimeError(f"Failed to open intrinsics file: {path}")
    k = fs.getNode("K").mat()
    d = fs.getNode("D").mat()
    fs.release()
    if k is None or d is None:
        raise RuntimeError("Intrinsics file missing K or D.")
    return np.asarray(k, dtype=float), np.asarray(d, dtype=float).reshape(-1)


def save_extrinsics(
    path: str,
    rvec_world_to_cam: np.ndarray,
    tvec_world_to_cam: np.ndarray,
    reproj_rmse_px: float,
) -> None:
    fs = cv2.FileStorage(path, cv2.FILE_STORAGE_WRITE)
    fs.write("rvec_world_to_cam", rvec_world_to_cam.reshape(3, 1))
    fs.write("tvec_world_to_cam", tvec_world_to_cam.reshape(3, 1))
    fs.write("extrinsics_reprojection_rmse_px", float(reproj_rmse_px))
    fs.release()


def get_extrinsics(camera_index: int, k: np.ndarray, d: np.ndarray):
    print("\n=== EXTRINSICS: POOL-PLANE ARUCO ===")
    print(f"Uses {EXTRINSICS_POOL_MARKER_COUNT} fixed ArUco markers.")
    print("World frame: define origin and axes (e.g. pool corner, Z up).")
    print(f"Marker side length is fixed at {DEFAULT_MARKER_SIZE_M} m (OpenCV uses meters).")
    print("Orientation is fixed: roll=pitch=yaw=0 (flat, aligned with world axes).")
    if USE_EXTRINSICS_MARKER_PRESET:
        print("Marker positions: from EXTRINSICS_PRESET_MARKERS_INCHES.")
    else:
        print("For each marker, enter: id, x, y [inches] (z=0 assumed, flat on pool plane).")

    marker_size_m = DEFAULT_MARKER_SIZE_M
    print(f"Using marker side length = {marker_size_m} m ({marker_size_m * 100:.0f} cm).")

    if USE_EXTRINSICS_MARKER_PRESET:
        if len(EXTRINSICS_PRESET_MARKERS_INCHES) != EXTRINSICS_POOL_MARKER_COUNT:
            raise RuntimeError(
                "EXTRINSICS_PRESET_MARKERS_INCHES must have EXTRINSICS_POOL_MARKER_COUNT rows."
            )

    # marker_id -> (cx_m, cy_m, cz_m, yaw_deg, pitch_deg, roll_deg); angles always 0
    marker_layout: Dict[int, Tuple[float, float, float, float, float, float]] = {}
    entries: List[Tuple[int, float, float, float]] = []
    if USE_EXTRINSICS_MARKER_PRESET:
        entries = [(int(a), float(b), float(c), float(d)) for a, b, c, d in EXTRINSICS_PRESET_MARKERS_INCHES]
    else:
        for idx in range(EXTRINSICS_POOL_MARKER_COUNT):
            raw = input(
                f"Marker {idx + 1}/{EXTRINSICS_POOL_MARKER_COUNT}: id, x_in, y_in\n"
                f"(example: 0, 0, 0): "
            ).strip()
            parts = [p.strip() for p in raw.split(",")]
            if len(parts) != 3:
                raise RuntimeError(
                    "Expected 3 comma-separated values: id, x_in, y_in (inches). z=0 assumed."
                )
            entries.append((int(parts[0]), float(parts[1]), float(parts[2]), 0.0))

    for mid, x_in, y_in, z_in in entries:
        cx = x_in * INCH_TO_M
        cy = y_in * INCH_TO_M
        cz = z_in * INCH_TO_M
        marker_layout[mid] = (cx, cy, cz, 0.0, 0.0, 0.0)
        print(
            f"  -> id {mid}: center ({cx:.5f}, {cy:.5f}, {cz:.5f}) m "
            f"[from ({x_in:g}, {y_in:g}) in]; z=0, orient (0,0,0) fixed"
        )

    aruco_dict = cv2.aruco.getPredefinedDictionary(ARUCO_DICT)
    detector = cv2.aruco.ArucoDetector(aruco_dict, cv2.aruco.DetectorParameters())

    cam = cv2.VideoCapture(camera_index)
    cam.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cam.set(cv2.CAP_PROP_FRAME_WIDTH, 1440)
    cam.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
    if not cam.isOpened():
        raise RuntimeError(f"Failed to open camera index {camera_index}.")

    required_ids = set(marker_layout.keys())
    num_captures_target = 50

    cv2.namedWindow("ExtrinsicsCapture", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("ExtrinsicsCapture", 960, 720)
    print(
        f"Auto-capture: waiting until ALL marker IDs {sorted(required_ids)} appear in one frame. "
        f"Will capture {num_captures_target} such frames, then solve. Press 'q' to abort."
    )

    object_points_all = []
    image_points_all = []
    frame_size = None
    captures_done = 0

    def _append_extrinsics_sample(corners, ids_arr) -> int:
        """Append world/image points for each configured marker in this detection."""
        used = 0
        for i, tag_id in enumerate(ids_arr.flatten()):
            tid = int(tag_id)
            if tid not in marker_layout:
                continue
            cx, cy, cz, yaw, pitch, roll = marker_layout[tid]
            world_corners = board_marker_corners_world(
                center_xyz=(cx, cy, cz),
                marker_size_m=marker_size_m,
                yaw_deg=yaw,
                pitch_deg=pitch,
                roll_deg=roll,
            )
            img_corners = corners[i].reshape(4, 2).astype(float)
            object_points_all.append(world_corners)
            image_points_all.append(img_corners)
            used += 1
        return used

    while captures_done < num_captures_target:
        ok, frame = cam.read()
        if not ok:
            continue
        frame_size = frame.shape[1], frame.shape[0]
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        corners, ids, _ = detector.detectMarkers(gray)
        draw = frame.copy()
        if ids is not None:
            cv2.aruco.drawDetectedMarkers(draw, corners, ids)

        found_ids = set(int(x) for x in ids.flatten()) if ids is not None else set()
        all_visible = ids is not None and required_ids.issubset(found_ids)

        status = f"Captures {captures_done}/{num_captures_target}"
        if all_visible:
            status += " | ALL IDs visible - saving sample"
        else:
            missing = required_ids - found_ids
            status += f" | missing IDs: {sorted(missing)}"
        cv2.putText(
            draw,
            status,
            (16, 32),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.7,
            (0, 255, 0) if all_visible else (0, 165, 255),
            2,
            cv2.LINE_AA,
        )

        cv2.imshow("ExtrinsicsCapture", draw)
        key = cv2.waitKey(1) & 0xFF
        if key == ord("q"):
            raise RuntimeError("Extrinsics capture aborted (q) before full capture.")

        if all_visible:
            used = _append_extrinsics_sample(corners, ids)
            if used != len(required_ids):
                raise RuntimeError(
                    f"Internal error: expected {len(required_ids)} markers in layout, got {used}."
                )
            captures_done += 1
            print(f"Auto-capture {captures_done}/{num_captures_target}: all {len(required_ids)} markers OK.")

    cam.release()
    cv2.destroyWindow("ExtrinsicsCapture")

    if not object_points_all:
        raise RuntimeError("No mapped marker points captured for extrinsics solve.")

    obj = np.vstack(object_points_all).astype(np.float32)
    img = np.vstack(image_points_all).astype(np.float32)

    success, rvec, tvec = cv2.solvePnP(obj, img, k, d, flags=cv2.SOLVEPNP_ITERATIVE)
    if not success:
        raise RuntimeError("solvePnP failed for extrinsics.")

    proj, _ = cv2.projectPoints(obj, rvec, tvec, k, d)
    proj = proj.reshape(-1, 2)
    rmse = np.sqrt(np.mean(np.sum((proj - img) ** 2, axis=1)))

    print("Solved world->camera extrinsics.")
    print("rvec_world_to_cam:\n", rvec.reshape(3))
    print("tvec_world_to_cam [m]:\n", tvec.reshape(3))
    print(f"Reprojection RMSE [px]: {rmse:.3f}")
    print(f"Frame size used: {frame_size}")

    return rvec.reshape(3, 1), tvec.reshape(3, 1), float(rmse)


def main():
    print(__doc__)
    camera_index = 1

    if not os.path.isfile(INTRINSICS_PATH):
        raise RuntimeError(
            f"Intrinsics file not found: {INTRINSICS_PATH}\n"
            "Update INTRINSICS_PATH or run your intrinsics workflow first."
        )

    k, d = load_intrinsics(INTRINSICS_PATH)
    print(f"Loaded intrinsics from: {INTRINSICS_PATH}")

    rvec_w2c, tvec_w2c, rmse = get_extrinsics(camera_index, k, d)
    save_extrinsics(CALIBRATION_EXTRINSICS_PATH, rvec_w2c, tvec_w2c, rmse)
    print(f"\nSaved extrinsics: {CALIBRATION_EXTRINSICS_PATH}")


if __name__ == "__main__":
    main()
