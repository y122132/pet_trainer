from ultralytics import YOLO

# 1. 모델별 특화 설정을 정의합니다.
# 모델파일명: [입력크기, 교정용_데이터]
model_config = {
    # 반려동물 행동 분석용 (사용자 커스텀 모델)
    #'pet_pose.pt': [640, '/home/yang/PROJECT/finetuning/calib.yaml'],
    
    # 사람-반려동물 인터랙션용 (사람 포즈 표준)
    'yolo11n-pose.pt': [640, 'coco8-pose.yaml'],
    
    # 사물 탐지용 (범용 사물 표준)
    #'yolo11n.pt': [640, 'coco128.yaml']
}

for model_name, config in model_config.items():
    img_size, yaml_file = config
    print(f"\n🚀 [작전 개시] {model_name} 변환 (Calibration: {yaml_file})")
    
    try:
        # 모델 로드
        model = YOLO(model_name)

        # TFLite 변환 실행
        # data: int8 양자화 시 정확도 유지를 위한 필수 교정 데이터
        # nms: Flutter 앱에서 결과값 처리를 간소화하기 위한 옵션
        model.export(
            format='tflite', 
            int8=True, 
            imgsz=img_size, 
            data=yaml_file,
            nms=False
        )
        
        print(f"✅ [임무 완수] {model_name} 변환 성공!")
        
    except Exception as e:
        print(f"❌ [에러 발생] {model_name} 변환 중 문제 발생: {e}")

print("\n🎯 모든 전용 모델의 모바일 최적화 공정이 완료되었습니다.")