from ultralytics import YOLO
import sys
import os

def check_model(path):
    print(f"Checking {path}...")
    if not os.path.exists(path):
        print(f"  [Error] File not found.")
        return

    try:
        model = YOLO(path)
        print(f"  Task: {model.task}")
        print(f"  Names: {model.names}")
        if hasattr(model.model, 'kpt_shape'):
             print(f"  Keyform Shape: {model.model.kpt_shape}")
        else:
             print(f"  Keypoints: Not supported (No kpt_shape)")
             
    except Exception as e:
        print(f"  [Error] Failed to load: {e}")
    print("-" * 30)

if __name__ == "__main__":
    check_model("epoch50.pt")
    check_model("test_best.pt")
    check_model("yolo11n-pose.pt")
