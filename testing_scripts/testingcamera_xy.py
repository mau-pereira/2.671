import cv2
import numpy as np
import time
import matplotlib.pyplot as plt

### CONFIG ###
TARGET_TAG_ID = 4
SAMPLE_RATE = 50              # Hz
DURATION = 15                 # seconds

NUM_SAMPLES = SAMPLE_RATE * DURATION
DT = 1.0 / SAMPLE_RATE

### CAMERA SETUP (same as tracker.py) ###
cam = cv2.VideoCapture(1)
cam.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
cam.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
cam.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
width = cam.get(cv2.CAP_PROP_FRAME_WIDTH)
height = cam.get(cv2.CAP_PROP_FRAME_HEIGHT)
print(f"Resolution: {width:.0f}x{height:.0f}")

### ARUCO SETUP ###
aruco_dict = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_6X6_250)
aruco_parameters = cv2.aruco.DetectorParameters()
detector = cv2.aruco.ArucoDetector(aruco_dict, aruco_parameters)
tag_size = 0.2

### CALIBRATION SETUP (same as tracker.py) ###
fname = 'calibration_chessboard_4k_tank.yaml'
fs = cv2.FileStorage(fname, cv2.FILE_STORAGE_READ)
if not fs.isOpened():
    raise RuntimeError(f"Failed to open {fname}")
K = fs.getNode("K").mat()
D = fs.getNode("D").mat()
fs.release()
camera_matrix = np.asarray(K, dtype=float)
dist_coeffs = np.asarray(D, dtype=float).reshape(-1)

### CAPTURE ###
x_data = np.full(NUM_SAMPLES, np.nan)
y_data = np.full(NUM_SAMPLES, np.nan)

print(f"Capturing for {DURATION} seconds at {SAMPLE_RATE} Hz...")

for k in range(NUM_SAMPLES):
    t_start = time.perf_counter()

    ret, image = cam.read()
    if not ret:
        continue

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    corners, ids, _ = detector.detectMarkers(gray)

    if ids is not None:
        ids_flat = ids.flatten()
        idx = np.where(ids_flat == TARGET_TAG_ID)[0]
        if len(idx) == 0:
            idx = [0]
        i = idx[0]

        rvecs, tvecs, _ = cv2.aruco.estimatePoseSingleMarkers(
            corners, tag_size, camera_matrix, dist_coeffs)

        x_data[k] = tvecs[i][0][0]
        y_data[k] = tvecs[i][0][1]

    elapsed = time.perf_counter() - t_start
    sleep_time = DT - elapsed
    if sleep_time > 0:
        time.sleep(sleep_time)

cam.release()
print("Done. Plotting...")

### PLOT ###
valid = ~np.isnan(x_data)
plt.figure()
plt.plot(x_data[valid], y_data[valid], 'b.', markersize=5)
plt.xlabel('x (m)')
plt.ylabel('y (m)')
plt.title('ArUco Marker Trajectory')
plt.axis('equal')
plt.grid(True)
plt.tight_layout()
plt.show()
