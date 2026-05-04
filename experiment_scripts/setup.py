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
DESIRED_WIDTH = 1440
DESIRED_HEIGHT = 1080
DESIRED_FPS = 60
PROBE_SECONDS = 40


def make_frequency_checker(label: str = "loop", print_every_s: float = 2.0):
    """
    Return a callable you can invoke once per loop iteration to print frequency.

    Usage:
        freq_tick = make_frequency_checker(label="tracker", print_every_s=2.0)
        while True:
            ...
            freq_tick()
    """
    if print_every_s <= 0:
        raise ValueError("print_every_s must be > 0.")

    state = {
        "t_last_print": time.perf_counter(),
        "count": 0,
    }

    def tick():
        state["count"] += 1
        now = time.perf_counter()
        elapsed = now - state["t_last_print"]
        if elapsed >= print_every_s:
            hz = state["count"] / max(elapsed, 1e-9)
            print(f"[FREQ:{label}] {hz:.2f} Hz over {elapsed:.2f} s")
            state["count"] = 0
            state["t_last_print"] = now

    return tick


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
