#!/usr/bin/env python
"""
Read one ArUco marker trajectory in world coordinates using saved calibration.
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
SAMPLE_HZ = 45
DURATION_S = 3

FRAME_WIDTH = 1920
FRAME_HEIGHT = 1080
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
    if not cam.isOpened():
        raise RuntimeError(f"Failed to open camera index {CAMERA_INDEX}.")

    # Lock exposure so brightness does not drift during sampling.
    cam.set(cv2.CAP_PROP_AUTO_EXPOSURE, 1)
    cam.set(cv2.CAP_PROP_EXPOSURE, MANUAL_EXPOSURE)
    cam.set(cv2.CAP_PROP_GAIN, MANUAL_GAIN)

    vision_t = []
    vision_x = []

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
                vision_t.append(t_rel)
                vision_x.append(float(pw[0]))

    capture_elapsed_s = time.perf_counter() - t0
    cam.release()

    vision_t = np.asarray(vision_t, dtype=float)
    vision_x = np.asarray(vision_x, dtype=float)
    print(f"Capture loop wall time: {capture_elapsed_s:.3f} s (target {DURATION_S:.3f} s)")
    print(f"Vision detections: {vision_t.size}")

    fig, ax = plt.subplots(figsize=(8, 4))
    if vision_t.size > 0:
        ax.plot(vision_t, vision_x, "b.", markersize=4, label="x(t)")
    else:
        ax.text(
            0.5,
            0.5,
            "No valid x samples detected",
            transform=ax.transAxes,
            ha="center",
            va="center",
            color="red",
        )

    ax.set_xlabel("time (s)")
    ax.set_ylabel("x world (m)")
    ax.set_title(f"ArUco id {TARGET_TAG_ID}: x vs time")
    ax.grid(True)
    fig.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
