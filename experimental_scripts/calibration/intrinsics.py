# EMM 3/17/25

# from https://automaticaddison.com/how-to-perform-pose-estimation-using-an-aruco-marker/


#!/usr/bin/env python


'''

Welcome to the Camera Calibration Program!


This program:

- Performs camera calibration using a chessboard.

'''


from __future__ import print_function # Python 2/3 compatibility

import cv2 # Import the OpenCV library to enable computer vision

import numpy as np # Import the NumPy scientific computing library

import glob # Used to get retrieve files that have a specified pattern

import os


# Project: Camera Calibration Using Python and OpenCV

# Date created: 12/19/2021

# Python version: 3.8


# Chessboard dimensions

number_of_squares_X = 10 # Number of chessboard squares along the x-axis

number_of_squares_Y = 7 # Number of chessboard squares along the y-axis

nX = number_of_squares_X - 1 # Number of interior corners along x-axis

nY = number_of_squares_Y - 1 # Number of interior corners along y-axis

square_size = 0.023 # Size, in meters, of a square side

# Preview window: full-resolution frames are downscaled for imshow only (calibration still uses full size).
PREVIEW_MAX_WIDTH = 960
PREVIEW_MAX_HEIGHT = 540


def resize_for_preview(image_bgr, max_w=PREVIEW_MAX_WIDTH, max_h=PREVIEW_MAX_HEIGHT):
  h, w = image_bgr.shape[:2]
  scale = min(max_w / float(w), max_h / float(h))
  if scale >= 1.0:
    return image_bgr
  new_w = max(1, int(round(w * scale)))
  new_h = max(1, int(round(h * scale)))
  return cv2.resize(image_bgr, (new_w, new_h), interpolation=cv2.INTER_AREA)


# Set termination criteria. We stop either when an accuracy is reached or when

# we have finished a certain number of iterations.

criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)


# Define real world coordinates for points in the 3D coordinate frame

# Object points are (0,0,0), (1,0,0), (2,0,0) ...., (5,8,0)

object_points_3D = np.zeros((nX * nY, 3), np.float32)


# These are the x and y coordinates

object_points_3D[:,:2] = np.mgrid[0:nY, 0:nX].T.reshape(-1, 2)


object_points_3D = object_points_3D * square_size


# Store vectors of 3D points for all chessboard images (world coordinate frame)

object_points = []


# Store vectors of 2D points for all chessboard images (camera coordinate frame)

image_points = []


def main():
  # Get the file path for images in the calibration_images directory
  script_dir = os.path.dirname(os.path.abspath(__file__))
  image_dir = os.path.join(script_dir, "calibration_images")
  os.chdir(image_dir)

  cv2.namedWindow("Image", cv2.WINDOW_NORMAL)

  # Use all calibration images (deterministic order).
  images = sorted(glob.glob('*.jpg'))

  # Go through each chessboard image, one by one
  for image_file in images:
    print('testing image', str(image_file))

    # Load the image
    image = cv2.imread(image_file)

    # Convert the image to grayscale
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    # Find the corners on the chessboard
    success, corners = cv2.findChessboardCorners(gray, (nY, nX), None)

    # If the corners are found by the algorithm, draw them
    if success == True:
      # Append object points
      object_points.append(object_points_3D)

      # Find more exact corner pixels
      corners_2 = cv2.cornerSubPix(gray, corners, (11,11), (-1,-1), criteria)

      # Append image points
      image_points.append(corners_2)

      # Draw the corners
      cv2.drawChessboardCorners(image, (nY, nX), corners_2, success)

      preview = resize_for_preview(image)
      cv2.imshow("Image", preview)
      cv2.resizeWindow("Image", preview.shape[1], preview.shape[0])

      # Display the window for a short period. Used for testing.
      cv2.waitKey(100)

  # Perform camera calibration to return the camera matrix, distortion coefficients, rotation and translation vectors etc
  ret, mtx, dist, rvecs, tvecs = cv2.calibrateCamera(object_points,
                                                     image_points,
                                                     gray.shape[::-1],
                                                     None,
                                                     None)

  print(f"\nIntrinsics reprojection RMSE: {ret:.4f} px")

  # Save parameters to a file
  cv_file = cv2.FileStorage('calibration_chessboard_4k_tank.yaml', cv2.FILE_STORAGE_WRITE)
  cv_file.write('K', mtx)
  cv_file.write('D', dist)
  cv_file.release()

  # Load the parameters from the saved file
  cv_file = cv2.FileStorage('calibration_chessboard_4k_tank.yaml', cv2.FILE_STORAGE_READ)
  mtx = cv_file.getNode('K').mat()
  dst = cv_file.getNode('D').mat()
  cv_file.release()

  # Display key parameter outputs of the camera calibration process
  print("Camera matrix:")
  print(mtx)

  print("¥n Distortion coefficient:")
  print(dist)

  # Close all windows
  cv2.destroyAllWindows()


if __name__ == '__main__':
  print(__doc__)
  main()