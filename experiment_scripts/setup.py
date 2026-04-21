#!/usr/bin/env python
"""
Camera setup probe: reads negotiated resolution and FPS.
"""

import time

import cv2


# ---------------------------------------------------------------------
# User settings
# ---------------------------------------------------------------------
CAMERA_INDEX = 1
DESIRED_WIDTH = 3840
DESIRED_HEIGHT = 2160
DESIRED_FPS = 60
PROBE_SECONDS = 3.0


def main():
    cam = cv2.VideoCapture(CAMERA_INDEX)
    if not cam.isOpened():
        raise RuntimeError(f"Failed to open camera index {CAMERA_INDEX}.")

    cam.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cam.set(cv2.CAP_PROP_FRAME_WIDTH, DESIRED_WIDTH)
    cam.set(cv2.CAP_PROP_FRAME_HEIGHT, DESIRED_HEIGHT)
    cam.set(cv2.CAP_PROP_FPS, DESIRED_FPS)

    # Values reported by the backend after negotiation.
    negotiated_width = int(cam.get(cv2.CAP_PROP_FRAME_WIDTH))
    negotiated_height = int(cam.get(cv2.CAP_PROP_FRAME_HEIGHT))
    negotiated_fps = float(cam.get(cv2.CAP_PROP_FPS))

    # Measured FPS from live reads (often more reliable than CAP_PROP_FPS).
    frame_count = 0
    t0 = time.perf_counter()
    while (time.perf_counter() - t0) < PROBE_SECONDS:
        ok, _ = cam.read()
        if ok:
            frame_count += 1
    elapsed = max(time.perf_counter() - t0, 1e-9)
    measured_fps = frame_count / elapsed

    cam.release()

    # Stored camera capability/result variables you can import elsewhere.
    camera_width = negotiated_width
    camera_height = negotiated_height
    camera_fps_reported = negotiated_fps
    camera_fps_measured = measured_fps

    print(f"Requested: {DESIRED_WIDTH}x{DESIRED_HEIGHT} @ {DESIRED_FPS:.1f} FPS")
    print(f"Reported : {camera_width}x{camera_height} @ {camera_fps_reported:.2f} FPS")
    print(f"Measured : {camera_fps_measured:.2f} FPS over {PROBE_SECONDS:.1f}s")


if __name__ == "__main__":
    main()
