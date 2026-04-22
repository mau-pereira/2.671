#!/usr/bin/env python
"""
Angled-camera calibration workflow for pool tracking.

This script is organized in numbered sections:
  1) Get intrinsics (chessboard)
  2) Get extrinsics (fixed ArUco markers on pool plane)
  3) Get boat offset (marker frame -> boat frame)
  4) Testing: trajectory plot (ArUco ID 4 in world / pool frame)
"""

import glob
import os
import time
from typing import Dict, List, Tuple

import cv2
import matplotlib.pyplot as plt
import numpy as np


# -----------------------------------------------------------------------------
# Shared paths and constants
# -----------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INTRINSICS_PATH = os.path.join(
    SCRIPT_DIR, "calibration_images", "calibration_chessboard_4k_tank.yaml"
)
CALIBRATION_EXTRINSICS_PATH = os.path.join(SCRIPT_DIR, "calibration_extrinsics.yaml")
CALIBRATION_IMAGES_DIR = os.path.join(SCRIPT_DIR, "calibration_images")

ARUCO_DICT = cv2.aruco.DICT_6X6_250

# Pool layout: distances are entered in inches, stored in meters for OpenCV.
INCH_TO_M = 0.0254

# Physical marker printed square side (OpenCV / solvePnP use metres). 20 cm default.
DEFAULT_MARKER_SIZE_M = 0.2

# Section 2: how many fixed pool markers define world frame for extrinsics.
EXTRINSICS_POOL_MARKER_COUNT = 2

# If True, section 2 uses EXTRINSICS_PRESET_MARKERS_INCHES (no typing). If False, prompts.
USE_EXTRINSICS_MARKER_PRESET = True
# Each row: (aruco_id, x_in, y_in, z_in) inches, flat pool plane (z=0).
EXTRINSICS_PRESET_MARKERS_INCHES = (
    (0, 0.0, 0.0, 0.0),
    (2, 0.0, 100.0, 0.0),
)

# Section 4: same spirit as testingcamera_xy.py
SECTION4_TARGET_TAG_ID = 4
SECTION4_SAMPLE_HZ = 50
SECTION4_DURATION_S = 15


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


def save_intrinsics(path: str, k: np.ndarray, d: np.ndarray) -> None:
    fs = cv2.FileStorage(path, cv2.FILE_STORAGE_WRITE)
    fs.write("K", k)
    fs.write("D", d.reshape(-1, 1))
    fs.release()


def save_angled_calibration(
    path: str,
    rvec_world_to_cam: np.ndarray,
    tvec_world_to_cam: np.ndarray,
    reproj_rmse_px: float,
    boat_offset_rvec: np.ndarray,
    boat_offset_tvec: np.ndarray,
) -> None:
    fs = cv2.FileStorage(path, cv2.FILE_STORAGE_WRITE)
    fs.write("rvec_world_to_cam", rvec_world_to_cam.reshape(3, 1))
    fs.write("tvec_world_to_cam", tvec_world_to_cam.reshape(3, 1))
    fs.write("extrinsics_reprojection_rmse_px", float(reproj_rmse_px))
    fs.write("rvec_marker_to_boat", boat_offset_rvec.reshape(3, 1))
    fs.write("tvec_marker_to_boat", boat_offset_tvec.reshape(3, 1))
    fs.release()


def marker_origin_world_from_extrinsics(
    rvec_world_to_cam: np.ndarray,
    tvec_world_to_cam: np.ndarray,
    tvec_marker_in_cam: np.ndarray,
) -> np.ndarray:
    """
    Marker origin expressed in camera frame -> world/pool frame.
    P_cam = R_wc @ P_world + t_wc  =>  P_world = R_wc.T @ (P_cam - t_wc)
    """
    rvec_w2c = np.asarray(rvec_world_to_cam, dtype=float).reshape(3, 1)
    t_wc = np.asarray(tvec_world_to_cam, dtype=float).reshape(3)
    p_cam = np.asarray(tvec_marker_in_cam, dtype=float).reshape(3)
    R_wc, _ = cv2.Rodrigues(rvec_w2c)
    return R_wc.T @ (p_cam - t_wc)


def pixel_to_world_plane(
    u: float,
    v: float,
    k: np.ndarray,
    d: np.ndarray,
    rvec_world_to_cam: np.ndarray,
    tvec_world_to_cam: np.ndarray,
    world_z: float = 0.0,
) -> np.ndarray:
    """
    Map a pixel (u, v) to a point on the world plane at world_z via ray–plane intersection.

    1. Undistort pixel -> normalised camera ray direction.
    2. Express camera origin and ray in world frame.
    3. Intersect the ray with the horizontal plane world_z = const.
    Returns np.array([x_world, y_world, world_z]).
    """
    pts = np.array([[[u, v]]], dtype=np.float64)
    undist = cv2.undistortPoints(pts, k, d)
    ray_cam = np.array([undist[0, 0, 0], undist[0, 0, 1], 1.0], dtype=float)

    R_wc, _ = cv2.Rodrigues(np.asarray(rvec_world_to_cam, dtype=float).reshape(3, 1))
    t_wc = np.asarray(tvec_world_to_cam, dtype=float).reshape(3)
    cam_origin_world = -R_wc.T @ t_wc
    ray_world = R_wc.T @ ray_cam

    if abs(ray_world[2]) < 1e-12:
        return np.array([np.nan, np.nan, world_z])

    t_param = (world_z - cam_origin_world[2]) / ray_world[2]
    hit = cam_origin_world + t_param * ray_world
    return hit


def load_existing_angled(path: str):
    if not os.path.exists(path):
        return None
    fs = cv2.FileStorage(path, cv2.FILE_STORAGE_READ)
    if not fs.isOpened():
        return None
    data = {
        "rvec_world_to_cam": fs.getNode("rvec_world_to_cam").mat(),
        "tvec_world_to_cam": fs.getNode("tvec_world_to_cam").mat(),
        "rmse": fs.getNode("extrinsics_reprojection_rmse_px").real(),
        "rvec_marker_to_boat": fs.getNode("rvec_marker_to_boat").mat(),
        "tvec_marker_to_boat": fs.getNode("tvec_marker_to_boat").mat(),
    }
    fs.release()
    return data


# -----------------------------------------------------------------------------
# 1) GET INTRINSICS
# -----------------------------------------------------------------------------
def section_1_get_intrinsics() -> Tuple[np.ndarray, np.ndarray]:
    print("\n=== SECTION 1: GET INTRINSICS ===")

    number_of_squares_x = 10
    number_of_squares_y = 7
    nx = number_of_squares_x - 1
    ny = number_of_squares_y - 1
    square_size = 0.023

    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
    objp = np.zeros((nx * ny, 3), np.float32)
    objp[:, :2] = np.mgrid[0:ny, 0:nx].T.reshape(-1, 2)
    objp *= square_size

    image_paths = sorted(glob.glob(os.path.join(CALIBRATION_IMAGES_DIR, "*.jpg")))
    if not image_paths:
        raise RuntimeError(f"No .jpg images found in {CALIBRATION_IMAGES_DIR}")

    object_points = []
    image_points = []
    image_shape = None

    cv2.namedWindow("IntrinsicsPreview", cv2.WINDOW_NORMAL)

    for path in image_paths:
        img = cv2.imread(path)
        if img is None:
            continue
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        ok, corners = cv2.findChessboardCorners(gray, (ny, nx), None)
        if ok:
            object_points.append(objp)
            corners_2 = cv2.cornerSubPix(gray, corners, (11, 11), (-1, -1), criteria)
            image_points.append(corners_2)
            image_shape = gray.shape[::-1]
            cv2.drawChessboardCorners(img, (ny, nx), corners_2, ok)
            preview = cv2.resize(img, (960, 540), interpolation=cv2.INTER_AREA)
            cv2.imshow("IntrinsicsPreview", preview)
            cv2.waitKey(50)

    cv2.destroyWindow("IntrinsicsPreview")

    if len(object_points) < 5:
        raise RuntimeError(f"Not enough valid chessboard images. Found {len(object_points)}.")

    ret, k, d, _, _ = cv2.calibrateCamera(object_points, image_points, image_shape, None, None)
    if not ret:
        raise RuntimeError("cv2.calibrateCamera failed.")

    save_intrinsics(INTRINSICS_PATH, k, d)
    print(f"Saved intrinsics to: {INTRINSICS_PATH}")
    print("K:\n", k)
    print("D:\n", d.reshape(-1))
    return k, d.reshape(-1)


# -----------------------------------------------------------------------------
# 2) GET EXTRINSICS (fixed ArUco markers in pool/world frame)
# -----------------------------------------------------------------------------
def section_2_get_extrinsics(camera_index: int, k: np.ndarray, d: np.ndarray):
    print("\n=== SECTION 2: GET EXTRINSICS (POOL-PLANE ARUCO) ===")
    print(f"Uses {EXTRINSICS_POOL_MARKER_COUNT} fixed ArUco markers.")
    print("World frame: define origin and axes (e.g. pool corner, Z up).")
    print(f"Marker side length is fixed at {DEFAULT_MARKER_SIZE_M} m (OpenCV uses metres).")
    print("Orientation is fixed: roll=pitch=yaw=0 (flat, aligned with world axes).")
    if USE_EXTRINSICS_MARKER_PRESET:
        print("Marker positions: from EXTRINSICS_PRESET_MARKERS_INCHES.")
    else:
        print("For each marker, enter one line:  id, x, y, z  [inches]  — center in world frame.")

    marker_size_m = DEFAULT_MARKER_SIZE_M
    print(f"Using marker side length = {marker_size_m} m ({marker_size_m * 100:.0f} cm).")

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
                f"Marker {idx + 1}/{EXTRINSICS_POOL_MARKER_COUNT}: id, x_in, y_in, z_in\n"
                f"(example: 0, 0, 0, 0  then  2, 0, 100, 0): "
            ).strip()
            parts = [p.strip() for p in raw.split(",")]
            if len(parts) != 4:
                raise RuntimeError(
                    "Expected 4 comma-separated values: id, x_in, y_in, z_in (inches)."
                )
            entries.append((int(parts[0]), float(parts[1]), float(parts[2]), float(parts[3])))

    for mid, x_in, y_in, z_in in entries:
        cx = x_in * INCH_TO_M
        cy = y_in * INCH_TO_M
        cz = z_in * INCH_TO_M
        marker_layout[mid] = (cx, cy, cz, 0.0, 0.0, 0.0)
        print(
            f"  -> id {mid}: center ({cx:.5f}, {cy:.5f}, {cz:.5f}) m "
            f"[from ({x_in:g}, {y_in:g}, {z_in:g}) in]; orient (0, 0, 0) deg (fixed)"
        )

    aruco_dict = cv2.aruco.getPredefinedDictionary(ARUCO_DICT)
    detector = cv2.aruco.ArucoDetector(aruco_dict, cv2.aruco.DetectorParameters())

    cam = cv2.VideoCapture(camera_index)
    cam.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cam.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
    cam.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
    if not cam.isOpened():
        raise RuntimeError(f"Failed to open camera index {camera_index}.")

    required_ids = set(marker_layout.keys())
    num_captures_target = 2

    cv2.namedWindow("ExtrinsicsCapture", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("ExtrinsicsCapture", 1280, 720)
    print(
        f"Auto-capture: waiting until ALL marker IDs {sorted(required_ids)} appear in one frame. "
        f"Will capture {num_captures_target} such frames, then solve. Press 'q' to abort."
    )

    object_points_all = []
    image_points_all = []
    frame_size = None
    captures_done = 0

    def _append_extrinsics_sample(
        corners,
        ids_arr,
    ) -> int:
        """Append world/image points for every configured marker in this detection. Returns count."""
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
            status += " | ALL IDs visible — saving sample"
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
            raise RuntimeError("Extrinsics capture aborted (q) before two full captures.")

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


# -----------------------------------------------------------------------------
# 3) GET BOAT OFFSET (marker frame -> boat frame)
# -----------------------------------------------------------------------------
def section_3_get_boat_offset():
    print("\n=== SECTION 3: GET BOAT OFFSET (MARKER->BOAT) ===")
    print("Provide the marker-to-boat transform from your physical measurements.")
    print("Convention used here:")
    print("  tvec_marker_to_boat: boat origin location expressed in marker frame [m]")
    print("  rvec_marker_to_boat: marker frame rotated into boat frame (Rodrigues)")

    raw_t = input("Enter tx,ty,tz [m] (example: 0.12,0.00,0.03): ").strip()
    tx, ty, tz = (float(v.strip()) for v in raw_t.split(","))

    raw_r = input("Enter roll,pitch,yaw [deg] marker->boat (example: 0,0,90): ").strip()
    roll_deg, pitch_deg, yaw_deg = (float(v.strip()) for v in raw_r.split(","))
    rvec = rodrigues_from_euler_xyz(roll_deg, pitch_deg, yaw_deg)
    tvec = np.array([[tx], [ty], [tz]], dtype=float)

    print("Saved boat offset values:")
    print("rvec_marker_to_boat:\n", rvec.reshape(3))
    print("tvec_marker_to_boat [m]:\n", tvec.reshape(3))
    return rvec, tvec


# -----------------------------------------------------------------------------
# 4) TESTING — trajectory of ArUco marker in world frame (like testingcamera_xy.py)
# -----------------------------------------------------------------------------
def section_4_trajectory_plot(
    camera_index: int,
    k: np.ndarray,
    d: np.ndarray,
    rvec_world_to_cam: np.ndarray,
    tvec_world_to_cam: np.ndarray,
    target_id: int = SECTION4_TARGET_TAG_ID,
    sample_hz: float = SECTION4_SAMPLE_HZ,
    duration_s: float = SECTION4_DURATION_S,
):
    """
    Timed capture using ray–plane intersection (no estimatePoseSingleMarkers).
    Detects ArUco marker centroid in pixels, undistorts, casts a ray through the
    camera extrinsics, and intersects the world z=0 pool plane.
    Plots x vs y.
    """
    print("\n=== SECTION 4: TRAJECTORY TEST (ray–plane) ===")
    num_samples = int(round(sample_hz * duration_s))
    dt = 1.0 / sample_hz
    print(
        f"Tracking ArUco id {target_id} for {duration_s} s at {sample_hz} Hz "
        f"({num_samples} samples). Move the marker; close the plot window when done."
    )

    aruco_dict = cv2.aruco.getPredefinedDictionary(ARUCO_DICT)
    detector = cv2.aruco.ArucoDetector(aruco_dict, cv2.aruco.DetectorParameters())

    cam = cv2.VideoCapture(camera_index)
    cam.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cam.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
    cam.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
    if not cam.isOpened():
        raise RuntimeError(f"Failed to open camera index {camera_index}.")

    # Lock exposure and gain so brightness doesn't drift between frames.
    cam.set(cv2.CAP_PROP_AUTO_EXPOSURE, 1)       # 1 = manual on many backends
    cam.set(cv2.CAP_PROP_EXPOSURE, -6)            # typical value; tune if too dark/bright
    cam.set(cv2.CAP_PROP_GAIN, 0)
    print("Exposure locked (manual). Adjust EXPOSURE value in script if image is too dark.")

    x_data = np.full(num_samples, np.nan)
    y_data = np.full(num_samples, np.nan)

    cv2.namedWindow("Section4Live", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("Section4Live", 1280, 720)

    for sample_k in range(num_samples):
        t_start = time.perf_counter()

        ret, image = cam.read()
        if not ret:
            continue

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        corners, ids, _ = detector.detectMarkers(gray)
        draw = image.copy()

        detected = False
        wx, wy = np.nan, np.nan

        if ids is not None:
            cv2.aruco.drawDetectedMarkers(draw, corners, ids)
            ids_flat = ids.flatten()
            hit = np.where(ids_flat == target_id)[0]
            if hit.size > 0:
                i = int(hit[0])
                crn = corners[i].reshape(4, 2)
                cx = float(np.mean(crn[:, 0]))
                cy = float(np.mean(crn[:, 1]))
                cv2.circle(draw, (int(cx), int(cy)), 6, (0, 255, 0), -1)

                pw = pixel_to_world_plane(
                    cx, cy, k, d,
                    rvec_world_to_cam, tvec_world_to_cam,
                    world_z=0.0,
                )
                wx, wy = pw[0], pw[1]
                x_data[sample_k] = wx
                y_data[sample_k] = wy
                detected = True

        pct = int(100 * (sample_k + 1) / num_samples)
        status = f"Sample {sample_k + 1}/{num_samples} ({pct}%)"
        if detected:
            status += f"  x={wx:.4f} y={wy:.4f} m"
        else:
            status += "  -- no id " + str(target_id)
        cv2.putText(draw, status, (16, 32), cv2.FONT_HERSHEY_SIMPLEX,
                     0.7, (0, 255, 0) if detected else (0, 0, 255), 2, cv2.LINE_AA)
        cv2.imshow("Section4Live", draw)
        cv2.waitKey(1)

        elapsed = time.perf_counter() - t_start
        sleep_time = dt - elapsed
        if sleep_time > 0:
            time.sleep(sleep_time)

    cam.release()
    cv2.destroyWindow("Section4Live")

    valid = ~np.isnan(x_data)
    n_valid = int(np.sum(valid))
    print(f"Done. Valid samples: {n_valid} / {num_samples}. Plotting...")

    fig, ax = plt.subplots(figsize=(5, 10))
    ax.plot(x_data[valid], y_data[valid], "b.", markersize=4)
    ax.set_xlabel("x world (m)")
    ax.set_ylabel("y world (m)")
    ax.set_title(f"ArUco id {target_id} — ray–plane (world z=0)")
    ax.set_xlim(0.0, 1.0)
    ax.set_ylim(0.0, 2.0)
    ax.xaxis.set_major_locator(plt.MultipleLocator(0.02))
    ax.yaxis.set_major_locator(plt.MultipleLocator(0.02))
    ax.set_aspect("equal")
    ax.grid(True)
    fig.tight_layout()
    plt.show()


def main():
    print(__doc__)
    print("\nNumbered sections:")
    print("  1) Get intrinsics")
    print("  2) Get extrinsics")
    print("  3) Get boat offset")
    print("  4) Trajectory test (marker 4, world x–y plot)")

    run_1 = input("\nRun section 1 (chessboard intrinsics)? [y/N]: ").strip().lower() == "y"
    run_2 = input("Run section 2 (pool ArUco extrinsics)? [y/N]: ").strip().lower() == "y"
    run_3 = input("Run section 3 (boat offset)? [y/N]: ").strip().lower() == "y"
    run_4 = input("Run section 4 (trajectory plot, marker 4)? [y/N]: ").strip().lower() == "y"

    camera_index = 1

    # -------------------------------------------------------------------------
    # Section 1
    # -------------------------------------------------------------------------
    if run_1:
        k, d = section_1_get_intrinsics()
    else:
        if not os.path.isfile(INTRINSICS_PATH):
            raise RuntimeError(
                f"Intrinsics file not found: {INTRINSICS_PATH}\n"
                "Run section 1 once, or place calibration_chessboard_4k_tank.yaml there."
            )
        k, d = load_intrinsics(INTRINSICS_PATH)
        print(f"Loaded intrinsics from: {INTRINSICS_PATH}")

    # -------------------------------------------------------------------------
    # Section 2
    # -------------------------------------------------------------------------
    if run_2:
        rvec_w2c, tvec_w2c, rmse = section_2_get_extrinsics(camera_index, k, d)
    else:
        prior = load_existing_angled(CALIBRATION_EXTRINSICS_PATH)
        if (
            prior is None
            or prior["rvec_world_to_cam"] is None
            or prior["tvec_world_to_cam"] is None
        ):
            raise RuntimeError(
                f"No extrinsics in {CALIBRATION_EXTRINSICS_PATH}. Run section 2 once."
            )
        rvec_w2c = prior["rvec_world_to_cam"]
        tvec_w2c = prior["tvec_world_to_cam"]
        rmse = float(prior["rmse"]) if prior["rmse"] is not None else float("nan")
        print(f"Loaded extrinsics from: {CALIBRATION_EXTRINSICS_PATH}")

    # -------------------------------------------------------------------------
    # Section 3
    # -------------------------------------------------------------------------
    if run_3:
        rvec_m2b, tvec_m2b = section_3_get_boat_offset()
    else:
        prior = load_existing_angled(CALIBRATION_EXTRINSICS_PATH)
        if (
            prior is not None
            and prior["rvec_marker_to_boat"] is not None
            and prior["tvec_marker_to_boat"] is not None
        ):
            rvec_m2b = prior["rvec_marker_to_boat"]
            tvec_m2b = prior["tvec_marker_to_boat"]
            print(f"Loaded boat offset from: {CALIBRATION_EXTRINSICS_PATH}")
        else:
            rvec_m2b = np.zeros((3, 1), dtype=float)
            tvec_m2b = np.zeros((3, 1), dtype=float)
            print("Boat offset: no file data; using zeros (run section 3 to set).")

    save_angled_calibration(
        path=CALIBRATION_EXTRINSICS_PATH,
        rvec_world_to_cam=rvec_w2c,
        tvec_world_to_cam=tvec_w2c,
        reproj_rmse_px=rmse,
        boat_offset_rvec=rvec_m2b,
        boat_offset_tvec=tvec_m2b,
    )
    print(f"\nSaved calibration bundle: {CALIBRATION_EXTRINSICS_PATH}")

    # -------------------------------------------------------------------------
    # Section 4
    # -------------------------------------------------------------------------
    if run_4:
        section_4_trajectory_plot(
            camera_index,
            k,
            d,
            rvec_w2c,
            tvec_w2c,
        )


if __name__ == "__main__":
    main()
