#!/usr/bin/env python
"""
Plot world (x, y) trajectories from CSV recordings produced by full_laptop_system.py.

CSV format: header line
    timestamp,u_propeller_pwm,u_rudder_pwm,x,y,yaw
then rows of floats (NaNs when the marker was not visible).
"""

import argparse
import glob
import os

import matplotlib.pyplot as plt
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_RAWDATA_DIR = os.path.join(
    REPO_ROOT, "data_folder", "April22_data_processing", "rawdata_all_data"
)
DEFAULT_CSV_FILE = os.path.join(DEFAULT_RAWDATA_DIR, "invalid_prop1650rudder1800_1.csv")
PLOT_ALL_TRIALS = False  # Plot all trials. True: load all CSVs in DEFAULT_RAWDATA_DIR when no CLI file/dir is given.


def load_recording_csv(path: str) -> np.ndarray:
    """Load one recording file; returns array shape (N, 6)."""
    data = np.loadtxt(path, delimiter=",", skiprows=1)
    if data.ndim == 1:
        data = data.reshape(1, -1)
    if data.shape[1] != 6:
        raise ValueError(
            f"{path}: expected 6 columns after header, got shape {data.shape}"
        )
    return data


def plot_trajectories(paths: list[str]) -> None:
    paths = [os.path.normpath(p) for p in paths]
    for path in paths:
        if not os.path.isfile(path):
            raise FileNotFoundError(path)

        fig, ax = plt.subplots(figsize=(7, 7))
        data = load_recording_csv(path)
        x = data[:, 3]
        y = data[:, 4]
        m = np.isfinite(x) & np.isfinite(y)
        n_valid = int(np.sum(m))
        n_total = int(data.shape[0])
        if np.any(m):
            ax.plot(x[m], y[m], ".", markersize=4, color="k")
            ax.set_aspect("equal", adjustable="box")
        else:
            ax.text(
                0.5,
                0.5,
                "No valid trajectory samples (finite x, y) in this file",
                transform=ax.transAxes,
                ha="center",
                va="center",
                color="red",
            )

        ax.set_xlabel("x world (m)")
        ax.set_ylabel("y world (m)")
        ax.set_title(f"Trajectory: {os.path.basename(path)} ({n_valid}/{n_total} valid)")
        ax.grid(True)
        fig.tight_layout()

    plt.show()


def _collect_paths(args: argparse.Namespace) -> list[str]:
    if args.files:
        return list(args.files)
    if PLOT_ALL_TRIALS:
        pattern = os.path.join(DEFAULT_RAWDATA_DIR, args.glob_pattern)
        found = sorted(glob.glob(pattern))
        if not found:
            raise SystemExit(f"No files matched: {pattern}")
        return found
    if args.dir:
        pattern = os.path.join(os.path.normpath(args.dir), args.glob_pattern)
        found = sorted(glob.glob(pattern))
        if not found:
            raise SystemExit(f"No files matched: {pattern}")
        return found
    # No files/dir passed: use the default CSV file.
    if not os.path.isfile(DEFAULT_CSV_FILE):
        raise SystemExit(
            f"Default CSV file not found: {DEFAULT_CSV_FILE}. "
            "Pass file path(s) explicitly or use --dir."
        )
    return [DEFAULT_CSV_FILE]


def main():
    parser = argparse.ArgumentParser(
        description="Plot x–y world trajectory from full_laptop_system CSV recording(s)."
    )
    parser.add_argument(
        "files",
        nargs="*",
        help=(
            "CSV file path(s). If omitted, uses "
            "data_folder/April22_data_processing/rawdata_all_data/prop1625rudder2000_1.csv "
            "unless --dir is set."
        ),
    )
    parser.add_argument(
        "--dir",
        type=str,
        default=None,
        help=f"Directory of CSVs (default folder: {DEFAULT_RAWDATA_DIR})",
    )
    parser.add_argument(
        "--glob",
        dest="glob_pattern",
        type=str,
        default="*.csv",
        help="With --dir, which files to include (default: *.csv)",
    )
    args = parser.parse_args()
    if args.files and args.dir:
        parser.error("Pass either explicit file paths or --dir, not both.")

    paths = _collect_paths(args)
    plot_trajectories(paths)


if __name__ == "__main__":
    main()
