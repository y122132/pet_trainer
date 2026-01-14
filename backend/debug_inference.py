import cv2
from ultralytics import YOLO
import numpy as np
import sys

def debug_inference(video_path, model_path):
    print(f"Opening {video_path}...")
    cap = cv2.VideoCapture(video_path)
    ret, frame = cap.read()
    cap.release()
    
    if not ret:
        print("Failed to read frame")
        return

    print(f"Frame extracted: {frame.shape}")
    
    # Load Model
    print(f"Loading {model_path}...")
    model = YOLO(model_path)
    
    # Inference (Same settings as detector.py)
    print("Running Inference...")
    results = model(frame, conf=0.01, imgsz=1280) # Low conf to force detection
    
    r = results[0]
    print("-" * 30)
    print(f"Boxes: {len(r.boxes)}")
    if len(r.boxes) > 0:
        for i, box in enumerate(r.boxes):
            print(f"Box {i}: Cls={box.cls.item()}, Conf={box.conf.item():.4f}")
            
    print("-" * 30)
    print(f"Keypoints Object: {r.keypoints}")
    if r.keypoints is not None:
        print(f"Keypoints Shape: {r.keypoints.data.shape}")
        if len(r.keypoints.data) > 0:
            print(f"Keypoints[0] data sample: {r.keypoints.data[0][0]}") # First KP of first box
            
    # Visualize using YOLO's built-in plotter
    debug_result = r.plot()
    cv2.imwrite("debug_output.jpg", debug_result)
    print("Saved debug_output.jpg")

if __name__ == "__main__":
    debug_inference("bird.mp4", "epoch50.pt")
