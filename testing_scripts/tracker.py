
import cv2
import numpy as np

### CAMERA SETUP ###
# to check device number: # TODO 
# in terminal, run: v4l2-ctl --list-devices
# to view feed: ffplay /dev/video5
		
cam = cv2.VideoCapture(1) 
cam.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
# cam.set(cv2.CAP_PROP_FRAME_WIDTH, 3840) # 4k/high_res
# cam.set(cv2.CAP_PROP_FRAME_HEIGHT, 2160) # 4k/high_res
cam.set(cv2.CAP_PROP_FRAME_WIDTH, 1920) # 4k/high_res
cam.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080) # 4k/high_res
width = cam.get(cv2.CAP_PROP_FRAME_WIDTH)
height = cam.get(cv2.CAP_PROP_FRAME_HEIGHT)
print(width, height) # should print 3840, 2160


### ARUCO SETUP ###
aruco_dict = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_6X6_250)
aruco_parameters = cv2.aruco.DetectorParameters()
detector = cv2.aruco.ArucoDetector(aruco_dict, aruco_parameters)
tag_size = 0.199 # in meters,based on actual tag size # TODO

### CALIBRATION SETUP ###
fname = 'calibration_chessboard_4k_tank.yaml' # add your path to the calibration yaml file here # TODO
fs = cv2.FileStorage(fname, cv2.FILE_STORAGE_READ)
if not fs.isOpened():
    raise RuntimeError(f"Failed to open {fname}")
K = fs.getNode("K").mat()
D = fs.getNode("D").mat()
fs.release()
camera_matrix = np.asarray(K, dtype=float)
dist_coeffs = np.asarray(D, dtype=float).reshape(-1)

prev_tags = {}

cv2.namedWindow('image', cv2.WINDOW_NORMAL)
cv2.resizeWindow('image', 1280, 720)

while True:
    ret, image = cam.read()
    if ret: # if frame was successfully read
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        corners, ids, rejectedCandidates = detector.detectMarkers(gray)
		
        if ids is not None:
            center_pixel = []
            for c in range(len(corners)): # get center pixel of each tag
                for corner in corners[c]:
                    cx = int(np.mean(corner[:, 0]))
                    cy = int(np.mean(corner[:, 1]))
                    center_pixel.append((cx, cy))
					
            rvecs, tvecs, _ = cv2.aruco.estimatePoseSingleMarkers(corners, tag_size, camera_matrix, dist_coeffs) 
            for i, tag_id in enumerate(ids.flatten()):
                rvec = rvecs[i]
                tvec = tvecs[i]
				
                # draw line from center to top on image and publish annotated image
                cv2.drawFrameAxes(image, camera_matrix, dist_coeffs, rvec, tvec, 0.1)

                # draw dot in center of tag
                cv2.circle(image, center_pixel[i], 5, (0, 255, 0), -1)

                # draw green line of track of single tag
                if tag_id in prev_tags:
                    for c in range(50):  # draw last 50 points
                        idx = len(prev_tags[tag_id]) - 1 - c
                        if idx < 0:
                            break
                        cv2.line(image, prev_tags[tag_id][idx][0], prev_tags[tag_id][idx-1][0], (0, 0, 0), 2)
                    prev_tags[tag_id].append([center_pixel[i], rvec, tvec])
                else:
                    prev_tags[tag_id] = [[center_pixel[i], rvec, tvec]]

    cv2.imshow('image', image)

    if cv2.waitKey(1) & 0xFF == ord('q'):
        cam.release()
        cv2.destroyAllWindows()
        break

