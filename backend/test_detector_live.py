import sys
import os
import cv2
import numpy as np

# 경로 설정 (backend 디렉토리에서 실행 전제)
sys.path.append(os.getcwd())

from app.ai_core.vision import detector

def test_inference():
    print("=== Unit Test Start ===")
    # 모델 로드
    try:
        detector.load_models()
    except Exception as e:
        print(f"Model Load Error: {e}")
        return

    # 이미지 로드 (강아지)
    img_path = "test_dog.jpg"
    if not os.path.exists(img_path):
        print(f"Error: {img_path} not found.")
        return

    with open(img_path, "rb") as f:
        image_bytes = f.read()

    # 추론 실행 (class_id 16 = dog)
    print("Running inference on dog image (target=16)...")
    # difficulty='easy' ensures conf threshold 0.3
    result = detector.process_frame(image_bytes, mode="playing", target_class_id=16, difficulty="easy")
    
    print(f"Success: {result.get('success')}")
    print(f"Conf Score: {result.get('conf_score')}")
    print(f"BBox: {result.get('bbox')}")
    print(f"Message: {result.get('message')}")
    
    if result.get('conf_score', 0) > 0:
        print("PASS: Dog detected successfully.")
    else:
        print("FAIL: Dog NOT detected (conf=0).")
        
    print("=== Unit Test End ===")

if __name__ == "__main__":
    test_inference()
