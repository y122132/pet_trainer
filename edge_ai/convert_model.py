from ultralytics import YOLO
import os

# 1. 변환 대상 모델 리스트 설정
# 파일명이 이미지와 일치하는지 확인하십시오.
model_files = [
    'pet_pose.pt',
    'yolo11n-pose.pt',
    'yolo11n.pt'
]

for model_name in model_files:
    print(f"\n🚀 [작전 개시] {model_name} 변환 시작...")
    
    try:
        # 2. .pt 모델 로드
        # 현재 스크립트와 같은 위치에 모델 파일이 있다고 가정합니다.
        model = YOLO(model_name)

        # 3. TFLite 포맷으로 변환 (Edge AI 최적화 옵션)
        # int8: 8비트 양자화로 모바일 가속 최적화
        # imgsz: 입력 이미지 크기 640 설정
        model.export(format='tflite', int8=True, imgsz=640)
        
        print(f"✅ [임무 완수] {model_name} 변환 성공!")
        
    except Exception as e:
        print(f"❌ [에러 발생] {model_name} 변환 중 문제 발생: {e}")

print("\n🎯 모든 모델 변환 공정이 완료되었습니다.")