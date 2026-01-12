from ultralytics import YOLO
import os

# 1. 변환 대상 모델 리스트 설정
# 파일명이 이미지와 일치하는지 확인하십시오.
# 1. 변환 대상 모델 설정 (파일명: 입력크기)
# Frontend(edge_detector_native.dart)에 하드코딩된 값과 정확히 일치해야 합니다.
model_config = {
    'pet_pose.pt': 1280,      # High Accuracy for Keypoints
    'yolo11n-pose.pt': 640,   # Human Pose (Interaction)
    'yolo11n.pt': 640         # Object Detection (Fast)
}

for model_name, size in model_config.items():
    print(f"\n🚀 [작전 개시] {model_name} (Size: {size}) 변환 시작...")
    
    try:
        # 2. .pt 모델 로드
        model = YOLO(model_name)

        # 3. TFLite 포맷으로 변환
        # int8: 8비트 양자화로 모바일 가속
        # imgsz: 모델별 전용 크기 적용
        model.export(format='tflite', int8=True, imgsz=size)
        
        print(f"✅ [임무 완수] {model_name} 변환 성공!")
        
    except Exception as e:
        print(f"❌ [에러 발생] {model_name} 변환 중 문제 발생: {e}")

print("\n🎯 모든 모델 변환 공정이 완료되었습니다.")