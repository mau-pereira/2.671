import os
import sys

import cv2

REQUESTED_WIDTH = 3840
REQUESTED_HEIGHT = 2160

# def _fourcc_to_str(cap: cv2.VideoCapture) -> str:
#     code = int(cap.get(cv2.CAP_PROP_FOURCC))
#     return "".join(chr((code >> (8 * i)) & 0xFF) for i in range(4))


def main() -> None:
    base_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(base_dir, "calibration_images")
    os.makedirs(output_dir, exist_ok=True)

    cap = (
        cv2.VideoCapture(1, cv2.CAP_DSHOW)
        if sys.platform == "win32"
        else cv2.VideoCapture(1)
    )
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, REQUESTED_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, REQUESTED_HEIGHT)

    if not cap.isOpened():
        print("Error: could not open webcam.")
        return

    # prop_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    # prop_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    # print(f"Requested resolution: {REQUESTED_WIDTH}x{REQUESTED_HEIGHT}")
    # print(f"Device reports (CAP_PROP): {prop_w}x{prop_h}, FOURCC={_fourcc_to_str(cap)!r}")

    cv2.namedWindow("Calibration Capture", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("Calibration Capture", 480, 270)

    print(f'Saving all images to this folder "{output_dir}"')
    print("Press 's' to save image, 'q' to quit.")

    existing_images = [
        name for name in os.listdir(output_dir)
        if name.lower().startswith("img") and name.lower().endswith(".jpg")
    ]
    image_count = len(existing_images)
    # verified = False
    while True:
        ok, frame = cap.read()
        if not ok:
            print("Error: could not read frame from webcam.")
            break

        # if not verified:
        #     fh, fw = frame.shape[:2]
        #     print(f"Actual frame size (from image array): {fw}x{fh}")
        #     if (fw, fh) != (prop_w, prop_h):
        #         print(
        #             f"  Note: array size {fw}x{fh} != CAP_PROP {prop_w}x{prop_h} "
        #             "(driver/metadata can disagree)."
        #         )
        #     verified = True

        cv2.imshow("Calibration Capture", frame)
        key = cv2.waitKey(1) & 0xFF

        if key == ord("s"):
            filename = f"img{image_count + 1}.jpg"
            save_path = os.path.join(output_dir, filename)
            cv2.imwrite(save_path, frame)
            image_count += 1
            print(f"Saved image {image_count}")
        elif key == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
