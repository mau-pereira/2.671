"""
Smartphone as webcam via Camo Studio + OpenCV (same idea as):
https://medium.com/@saicoumar/how-to-use-a-smartphone-as-a-webcam-with-opencv-b68773db9ddd

1) List indices OpenCV can open (run this first to find Camo):
     python iphone.py list

2) Preview a feed (default index 1 — change the constant or pass a number):
     python iphone.py
     python iphone.py 1

Camo Studio must be running with the phone paired and selected.

Requests 3840x2160 + MJPEG; the actual size may be lower if Camo or the driver caps it.
"""

import sys

import cv2

# Replace with the index you got from `python iphone.py list` (often 1 if laptop cam is 0).
CAMERA_INDEX = 1
FRAME_WIDTH = 3840
FRAME_HEIGHT = 2160
LIST_MAX_INDEX = 10


def _fourcc_to_str(cap: cv2.VideoCapture) -> str:
    code = int(cap.get(cv2.CAP_PROP_FOURCC))
    return "".join(chr((code >> (8 * i)) & 0xFF) for i in range(4))


def _open_capture(index: int) -> cv2.VideoCapture:
    """Prefer DirectShow on Windows so virtual webcams (Camo) enumerate reliably."""
    if sys.platform == "win32":
        return cv2.VideoCapture(index, cv2.CAP_DSHOW)
    return cv2.VideoCapture(index)


def list_cameras(max_index: int = LIST_MAX_INDEX) -> list[int]:
    """Probe indices like the Medium article — see which cameras OpenCV can use."""
    print("Scanning camera indices (OpenCV)...")
    available: list[int] = []
    for i in range(max_index):
        cap = _open_capture(i)
        if not cap.isOpened():
            cap.release()
            continue
        ok, _ = cap.read()
        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        cap.release()
        if ok:
            print(f"  Index {i}: OK ({w}x{h})")
            available.append(i)
        else:
            print(f"  Index {i}: opened but no frame")
    if not available:
        print("  No cameras found. Is Camo Studio running with the phone selected?")
    else:
        print(f"Available indices: {available}")
    return available


def preview(index: int) -> None:
    cap = _open_capture(index)
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)

    if not cap.isOpened():
        print(f"Error: could not open camera at index {index}.")
        print("Run: python iphone.py list")
        return

    prop_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    prop_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"Camera index {index} opened.")
    print(f"  Requested resolution: {FRAME_WIDTH}x{FRAME_HEIGHT}")
    print(f"  Device reports (CAP_PROP): {prop_w}x{prop_h}, FOURCC={_fourcc_to_str(cap)!r}")
    print("Press 'q' to quit.")

    cv2.namedWindow("Camo / iPhone", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("Camo / iPhone", min(1280, prop_w), min(720, prop_h))

    verified = False
    while True:
        ok, frame = cap.read()
        if not ok:
            print("Error: could not read frame.")
            break

        if not verified:
            fh, fw = frame.shape[:2]
            print(f"  Actual frame size (from image array): {fw}x{fh}")
            if (fw, fh) != (prop_w, prop_h):
                print(
                    f"  Note: array size {fw}x{fh} != CAP_PROP {prop_w}x{prop_h} "
                    "(driver/metadata can disagree)."
                )
            verified = True

        cv2.imshow("Camo / iPhone", frame)
        if (cv2.waitKey(1) & 0xFF) == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()


def main() -> None:
    args = sys.argv[1:]

    if args and args[0].lower() in ("list", "scan", "-l", "--list"):
        list_cameras()
        return

    index = int(args[0]) if args else CAMERA_INDEX
    preview(index)


if __name__ == "__main__":
    main()
