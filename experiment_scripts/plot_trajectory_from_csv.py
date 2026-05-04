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
DEFAULT_RAWDATA_DIR = os.path.join(SCRIPT_DIR, "rawdata")
DEFAULT_CSV = os.path.join(DEFAULT_RAWDATA_DIR, "prop1675rudder2000_1.csv")


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
    fig, ax = plt.subplots(figsize=(7, 7))

    cmap = plt.get_cmap("tab10")
    any_points = False

    for i, path in enumerate(paths):
        if not os.path.isfile(path):
            raise FileNotFoundError(path)
        data = load_recording_csv(path)
        x = data[:, 3]
        y = data[:, 4]
        m = np.isfinite(x) & np.isfinite(y)
        n_valid = int(np.sum(m))
        n_total = int(data.shape[0])
        label = f"{os.path.basename(path)} ({n_valid}/{n_total} valid)"
        color = cmap(i % 10)
        if np.any(m):
            any_points = True
            ax.plot(x[m], y[m], ".", markersize=4, color=color, label=label)
        else:
            ax.plot([], [], "o", color=color, label=f"{os.path.basename(path)} (no valid xy)")

    if any_points:
        ax.set_aspect("equal", adjustable="box")
    else:
        ax.text(
            0.5,
            0.5,
            "No valid trajectory samples (finite x, y) in given file(s)",
            transform=ax.transAxes,
            ha="center",
            va="center",
            color="red",
        )

    ax.set_xlabel("x world (m)")
    ax.set_ylabel("y world (m)")
    ax.set_title("Trajectory from recording(s)")
    ax.grid(True)
    if len(paths) > 1:
        ax.legend(loc="best", fontsize=8)
    fig.tight_layout()
    plt.show()


def _collect_paths(args: argparse.Namespace) -> list[str]:
    if args.files:
        return list(args.files)
    if args.dir:
        pattern = os.path.join(os.path.normpath(args.dir), args.glob_pattern)
        found = sorted(glob.glob(pattern))
        if not found:
            raise SystemExit(f"No files matched: {pattern}")
        return found
    return [DEFAULT_CSV]


def main():
    parser = argparse.ArgumentParser(
        description="Plot x–y world trajectory from full_laptop_system CSV recording(s)."
    )
    parser.add_argument(
        "files",
        nargs="*",
        help=(
            "CSV file path(s). If omitted, uses the default example under "
            "experiment_scripts/rawdata/ unless --dir is set."
        ),
    )
    parser.add_argument(
        "--dir",
        type=str,
        default=None,
        help=f"Directory of CSVs (default rawdata folder: {DEFAULT_RAWDATA_DIR})",
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
