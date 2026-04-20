"""
Generate ArUco markers (OpenCV DICT_6X6_250) as square PNGs for pasting into Word.

Each PNG is 20 cm x 20 cm when printed at the embedded resolution (300 DPI).
Default: ids 0,1,2,3,4.

Matches testing_experimental_scripts/tracker.py dictionary.

In Word: insert picture, then set size to exactly 20 cm x 20 cm if Word rescales.
"""

from __future__ import annotations

import argparse
import os
import sys

import cv2
import numpy as np

# Square output: physical size when printed at PRINT_DPI
SQUARE_SIDE_CM = 20.0
CM_PER_INCH = 2.54
PRINT_DPI = 300

DICT = cv2.aruco.DICT_6X6_250
ID_MAX = 249
DEFAULT_IDS = (0, 1, 2, 3, 4)


def _generate_marker_bitmap(dictionary: cv2.aruco.Dictionary, marker_id: int, side_px: int) -> np.ndarray:
    """Return uint8 grayscale marker image (side_px x side_px)."""
    if hasattr(cv2.aruco, "generateImageMarker"):
        return cv2.aruco.generateImageMarker(dictionary, marker_id, side_px)
    img = np.zeros((side_px, side_px), dtype=np.uint8)
    cv2.aruco.drawMarker(dictionary, marker_id, side_px, img, 1)
    return img


def main() -> None:
    parser = argparse.ArgumentParser(description="ArUco markers 20 cm square PNGs (DICT_6X6_250).")
    parser.add_argument(
        "--ids",
        type=str,
        default="0,1,2,3,4",
        help="Comma-separated marker ids (default: 0,1,2,3,4).",
    )
    parser.add_argument(
        "--out-dir",
        default="",
        help="Output folder (default: same folder as this script).",
    )
    args = parser.parse_args()

    try:
        ids = [int(x.strip()) for x in args.ids.split(",") if x.strip() != ""]
    except ValueError:
        print("Error: --ids must be comma-separated integers.", file=sys.stderr)
        sys.exit(1)
    if not ids:
        ids = list(DEFAULT_IDS)

    for mid in ids:
        if not 0 <= mid <= ID_MAX:
            print(f"Error: marker id must be 0..{ID_MAX}, got {mid}.", file=sys.stderr)
            sys.exit(1)

    side_in = SQUARE_SIDE_CM / CM_PER_INCH
    side_px = int(round(side_in * PRINT_DPI))
    if side_px < 64:
        print("Error: computed image size too small.", file=sys.stderr)
        sys.exit(1)

    out_dir = args.out_dir or os.path.dirname(os.path.abspath(__file__))
    os.makedirs(out_dir, exist_ok=True)

    dictionary = cv2.aruco.getPredefinedDictionary(DICT)
    written = []
    for mid in ids:
        marker_gray = _generate_marker_bitmap(dictionary, mid, side_px)
        if marker_gray.ndim != 2:
            marker_gray = cv2.cvtColor(marker_gray, cv2.COLOR_BGR2GRAY)
        out_path = os.path.join(out_dir, f"aruco_6x6_250_id_{mid}.png")
        if not cv2.imwrite(out_path, marker_gray):
            print(f"Error: failed to write {out_path}", file=sys.stderr)
            sys.exit(1)
        written.append(out_path)

    print(
        f"Wrote {len(written)} file(s) at {side_px} x {side_px} px "
        f"({SQUARE_SIDE_CM:g} cm x {SQUARE_SIDE_CM:g} cm @ {PRINT_DPI} DPI):"
    )
    for p in written:
        print(f"  {p}")
    print("DICT_6X6_250. Set tracker.py tag_size to 0.20 (meters) if printed at 20 cm per side.")


if __name__ == "__main__":
    main()
