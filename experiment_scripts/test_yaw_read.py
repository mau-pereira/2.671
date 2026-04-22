#!/usr/bin/env python
"""
Read one ArUco marker yaw trajectory in world coordinates using saved calibration.
Uses corner ray-plane projection (fast) instead of estimatePoseSingleMarkers.
"""

import os
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
    "calibration_images_april21",
    "calibration_intrinsics_april21.yaml",
)
EXTRINSICS_PATH = os.path.join(
    SCRIPT_DIR,
    "calibration",
    "calibration_extrinsics_april21.yaml",
)

CAMERA_INDEX = 1
ARUCO_DICT = cv2.aruco.DICT_6X6_250
TARGET_TAG_ID = 0
DURATION_S = 30
SHOW_CAMERA_FEED = True

FRAME_WIDTH = 1920
FRAME_HEIGHT = 1080
CAMERA_FPS = 60
MANUAL_EXPOSURE = -6
MANUAL_GAIN = 0

WORLD_PLANE_Z = 0.0


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


def create_yaw_tracker(
    intrinsics_path: str = INTRINSICS_PATH,
    extrinsics_path: str = EXTRINSICS_PATH,
    aruco_dict_id: int = ARUCO_DICT,
):
    """Create reusable yaw-tracker resources for external scripts."""
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


def get_marker_yaw_world_from_frame(
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
    Return marker yaw (rad) in world frame from one camera frame.
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

    p_tl = pixel_to_world_plane_fast(
        float(crn[0, 0]),
        float(crn[0, 1]),
        k,
        d,
        r_cw,
        cam_origin_world,
        world_plane_z,
    )
    p_tr = pixel_to_world_plane_fast(
        float(crn[1, 0]),
        float(crn[1, 1]),
        k,
        d,
        r_cw,
        cam_origin_world,
        world_plane_z,
    )

    if not (np.isfinite(p_tl[0]) and np.isfinite(p_tl[1]) and np.isfinite(p_tr[0]) and np.isfinite(p_tr[1])):
        return None

    yaw_rad = np.arctan2(p_tr[1] - p_tl[1], p_tr[0] - p_tl[0])
    return float(yaw_rad)


def main():
    k, d = load_intrinsics(INTRINSICS_PATH)
    rvec_w2c, tvec_w2c = load_extrinsics(EXTRINSICS_PATH)

    print(f"Intrinsics: {INTRINSICS_PATH}")
    print(f"Extrinsics: {EXTRINSICS_PATH}")
    print("Reminder: open Camo Studio for better detection rate / effective Hz.")
    camo_open = input("Is Camo Studio open? [Y/n]: ").strip().lower()
    if camo_open in {"n", "no"}:
        print("Warning: detections/Hz are worse if Camo Studio is not open.")
    print(f"Tracking ArUco id {TARGET_TAG_ID} yaw for {DURATION_S} s (max-throughput mode).")
    if SHOW_CAMERA_FEED:
        print("Live camera preview enabled (press 'q' to stop early).")
    else:
        print("Live camera preview disabled.")

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

    if SHOW_CAMERA_FEED:
        cv2.namedWindow("YawReadLive", cv2.WINDOW_NORMAL)
        cv2.resizeWindow("YawReadLive", 1280, 720)

    vision_t = []
    vision_yaw_rad = []

    t0 = time.perf_counter()
    while True:
        t_rel = time.perf_counter() - t0
        if t_rel >= DURATION_S:
            break

        ret, image = cam.read()
        if not ret:
            continue

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        corners, ids, _ = detector.detectMarkers(gray)

        yaw_deg_live = None
        if ids is not None:
            ids_flat = ids.flatten()
            hit = np.where(ids_flat == TARGET_TAG_ID)[0]
            if hit.size > 0:
                i = int(hit[0])
                crn = corners[i].reshape(4, 2)  # TL, TR, BR, BL

                p_tl = pixel_to_world_plane_fast(
                    float(crn[0, 0]),
                    float(crn[0, 1]),
                    k,
                    d,
                    r_cw,
                    cam_origin_world,
                    WORLD_PLANE_Z,
                )
                p_tr = pixel_to_world_plane_fast(
                    float(crn[1, 0]),
                    float(crn[1, 1]),
                    k,
                    d,
                    r_cw,
                    cam_origin_world,
                    WORLD_PLANE_Z,
                )

                if np.isfinite(p_tl[0]) and np.isfinite(p_tr[0]):
                    yaw_rad = np.arctan2(p_tr[1] - p_tl[1], p_tr[0] - p_tl[0])
                    vision_t.append(t_rel)
                    vision_yaw_rad.append(float(yaw_rad))
                    yaw_deg_live = float(np.rad2deg(yaw_rad))

        if SHOW_CAMERA_FEED:
            draw = image.copy()
            if ids is not None:
                cv2.aruco.drawDetectedMarkers(draw, corners, ids)
            status = f"t={t_rel:.2f}s"
            if yaw_deg_live is None:
                status += f"  no id {TARGET_TAG_ID}"
                color = (0, 0, 255)
            else:
                status += f"  yaw={yaw_deg_live:.1f} deg"
                color = (0, 255, 0)
            cv2.putText(
                draw,
                status,
                (16, 32),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                color,
                2,
                cv2.LINE_AA,
            )
            cv2.imshow("YawReadLive", draw)
            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                print("Stopping early due to 'q' key.")
                break

    capture_elapsed_s = time.perf_counter() - t0
    cam.release()
    if SHOW_CAMERA_FEED:
        cv2.destroyWindow("YawReadLive")

    vision_t = np.asarray(vision_t, dtype=float)
    vision_yaw_rad = np.asarray(vision_yaw_rad, dtype=float)
    print(f"Capture loop wall time: {capture_elapsed_s:.3f} s (target {DURATION_S:.3f} s)")
    print(f"Vision detections: {vision_t.size}")

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(9, 7), sharex=True)
    if vision_t.size >= 2:
        yaw_unwrapped = np.unwrap(vision_yaw_rad)
        yaw_rate_rad_s = np.gradient(yaw_unwrapped, vision_t)
        yaw_deg = np.rad2deg(yaw_unwrapped)
        yaw_rate_deg_s = np.rad2deg(yaw_rate_rad_s)

        ax1.plot(vision_t, yaw_deg, "b.", markersize=4, label="yaw")
        ax2.plot(vision_t, yaw_rate_deg_s, "m.", markersize=4, label="yaw rate")
    elif vision_t.size == 1:
        yaw_deg = np.rad2deg(vision_yaw_rad)
        ax1.plot(vision_t, yaw_deg, "b.", markersize=4, label="yaw")
        ax2.text(
            0.5,
            0.5,
            "Need >= 2 samples for yaw rate",
            transform=ax2.transAxes,
            ha="center",
            va="center",
            color="red",
        )
    else:
        ax1.text(
            0.5,
            0.5,
            "No valid yaw samples detected",
            transform=ax1.transAxes,
            ha="center",
            va="center",
            color="red",
        )
        ax2.text(
            0.5,
            0.5,
            "No valid yaw-rate samples detected",
            transform=ax2.transAxes,
            ha="center",
            va="center",
            color="red",
        )

    ax1.set_ylabel("yaw (deg)")
    ax1.set_title(f"ArUco id {TARGET_TAG_ID}: world-frame yaw vs time")
    ax1.grid(True)

    ax2.set_xlabel("time (s)")
    ax2.set_ylabel("yaw rate (deg/s)")
    ax2.grid(True)

    fig.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
