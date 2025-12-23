import cv2
import numpy as np
import base64
from ultralytics import YOLO
from app.core.pet_behavior_config import PET_BEHAVIORS, DEFAULT_BEHAVIOR

# 전역 모델 변수 (최초 1회 로드)
model_pose = None
model_detect = None

def load_models():
    """
    YOLO AI 모델을 로드합니다.
    - model_pose: 교감 모드에서 사람의 위치/자세를 파악하기 위해 사용 (yolo11n-pose.pt)
    - model_detect: 반려동물 및 사물 인식을 위해 사용 (yolo11n.pt)
    """
    global model_pose, model_detect
    if model_pose is None:
        print("Loading YOLO models... (AI 모델 로딩 중)")
        model_pose = YOLO("yolo11n-pose.pt", verbose=False)
        model_detect = YOLO("yolo11n.pt", verbose=False) 
        print("YOLO models loaded. (로딩 완료)")
    return model_pose, model_detect

def calculate_iou(box1, box2):
    """
    두 박스 간의 IoU (Intersection over Union)를 계산합니다. (겹침 정도 파악)
    box: [x1, y1, x2, y2] (정규화된 좌표)
    """
    xA = max(box1[0], box2[0])
    yA = max(box1[1], box2[1])
    xB = min(box1[2], box2[2])
    yB = min(box1[3], box2[3])

    # 교차 영역(Intersection)의 넓이
    interArea = max(0, xB - xA) * max(0, yB - yA)
    if interArea == 0: return 0.0

    # 각 박스의 넓이
    box1Area = (box1[2] - box1[0]) * (box1[3] - box1[1])
    box2Area = (box2[2] - box2[0]) * (box2[3] - box2[1])

    # 합집합 영역(Union)
    unionArea = box1Area + box2Area - interArea
    if unionArea == 0: return 0.0

    return interArea / unionArea

def calculate_overlap_ratio(pet_box, obj_box):
    """
    물체가 반려동물 영역 안에 얼마나 들어와 있는지 계산 (포함 비율)
    """
    xA = max(pet_box[0], obj_box[0])
    yA = max(pet_box[1], obj_box[1])
    xB = min(pet_box[2], obj_box[2])
    yB = min(pet_box[3], obj_box[3])
    
    interArea = max(0, xB - xA) * max(0, yB - yA)
    objArea = (obj_box[2] - obj_box[0]) * (obj_box[3] - obj_box[1])
    
    if objArea == 0: return 0.0
    return interArea / objArea # 물체 면적 대비 겹친 비율

def process_frame(image_bytes: bytes, mode: str = "playing", target_class_id: int = 16, difficulty: str = "easy") -> dict:
    """
    프론트엔드에서 전송된 프레임을 분석하여 반려동물의 행동을 판단합니다.
    
    Args:
        image_bytes: 바이너리 이미지 데이터 (JPEG 등)
        mode: 현재 게임 모드 ('playing', 'feeding', 'interaction')
        target_class_id: 감지할 반려동물의 YOLO Class ID
        difficulty: 난이도 설정
        
    Returns:
        dict: 감지 결과, 성공 여부, 피드백 메시지 등
    """
    # 1. 모델 로드 (명시적 초기화: 전역 변수 대신 반환값 사용)
    model_pose, model_detect = load_models()
    
    # 1. 바이너리 이미지 디코딩
    try:
        # base64 디코딩 단계 생략 (직접 bytes 수신)
        np_data = np.frombuffer(image_bytes, np.uint8)
        frame = cv2.imdecode(np_data, cv2.IMREAD_COLOR)
        
        if frame is None:
            return {"success": False, "message": "이미지 디코딩 실패"}
            
    except Exception as e:
        return {"success": False, "message": f"이미지 디코딩 에러: {str(e)}"}

    height, width, _ = frame.shape
    print(f"[Detector] Input Image Size: {width}x{height} (Ratio: {width/height:.2f})", flush=True)

    # ---------------------------------------------------------
    # 2. 반려동물 & 사물 탐지 (YOLO Object Detection)
    # ---------------------------------------------------------
    
    # 난이도에 따른 감지 임계값(Threshold) 조절 (초기 인식률 향상을 위해 0.4 -> 0.3으로 완화)
    det_conf = 0.5 if difficulty == "hard" else 0.3
    
    # [Critical Fix] BGR -> RGB 변환
    # OpenCV는 BGR을 사용하지만, YOLO 모델(Ultralytics)은 RGB를 기대함.
    # 색상이 반전되면(예: 갈색 강아지 -> 파란색) 모델이 오인식(사람 등)할 수 있음.
    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    
    # YOLO 추론 수행 (imgsz=640 명시하여 비율 유지 리사이징/패딩 보장)
    results_detect = model_detect(frame_rgb, conf=det_conf, imgsz=640, verbose=False)
    
    found_pet = False
    pet_box = [] # [x1, y1, x2, y2] (정규화된 좌표)
    best_conf = 0.0
    
    props_detected = [] 
    prop_boxes = {} # class_id -> [x1, y1, x2, y2]
    
    if results_detect and results_detect[0].boxes:
        for box in results_detect[0].boxes:
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])
            
            # 좌표 정규화 (0.0 ~ 1.0) 
            # 화면 크기가 달라도 일관된 처리를 위해 절대 좌표 대신 비율 사용
            x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
            nx1, ny1, nx2, ny2 = float(x1/width), float(y1/height), float(x2/width), float(y2/height)
            current_box = [nx1, ny1, nx2, ny2]

            # A. 반려동물 찾기 (설정된 target_class_id와 일치하는지 확인)
            if cls_id == target_class_id:
                if conf > best_conf: # 가장 신뢰도 높은 객체 선택
                    best_conf = conf
                    found_pet = True
                    pet_box = current_box
            
            # [Debug] 타겟 ID와 상관없이 가장 신뢰도 높은 객체 기록 (오인식 원인 분석용)
            # 16(dog), 15(cat) 등 펫 관련 클래스라면 특히 주의
            pass

    # ---------------------------------------------------------
    # 3. 로직 처리 (상호작용/Overlap 판단)
    # ---------------------------------------------------------
    
    # [Debug] 전체 탐지 결과 요약 (디버깅용)
    all_detections_summary = ""
    max_conf_any = 0.0
    max_conf_cls = -1
    
    if results_detect and results_detect[0].boxes:
        for box in results_detect[0].boxes:
             c = float(box.conf[0])
             cid = int(box.cls[0])
             if c > max_conf_any:
                 max_conf_any = c
                 max_conf_cls = cid
             all_detections_summary += f"{cid}({c:.2f}) "

    if not found_pet:
        return {
            "success": False,
            "message": f"반려동물 찾는 중... (Raw: {all_detections_summary})", 
            "feedback_message": "pet_not_found",
            "keypoints": [],
            "width": width,
            "height": height,
            "conf_score": best_conf,
            "debug_max_conf": max_conf_any, # 타겟 무관 최고 점수
            "debug_max_cls": max_conf_cls   # 타겟 무관 최고 클래스
        }

    # 현재 모드에 필요한 타겟 물건 설정 가져오기
    pet_config = PET_BEHAVIORS.get(target_class_id, DEFAULT_BEHAVIOR)
    mode_config = pet_config.get(mode, pet_config["playing"]) 
    target_props = mode_config["targets"]
    
    # 화면에 타겟 물건이 하나라도 있는지 확인
    has_target = any(p in props_detected for p in target_props)
    
    # 상호작용 성공 여부 판단
    is_interacting = False
    distance_msg = ""
    
    if has_target:
        # 감지된 타겟들 중 가장 조건에 부합하는(가깝거나 겹친) 것 찾기
        max_overlap = 0.0
        min_distance = 9999.0
        
        # 반려동물 중심점
        pet_cx = (pet_box[0] + pet_box[2]) / 2
        pet_cy = (pet_box[1] + pet_box[3]) / 2

        for pid in target_props:
            if pid in prop_boxes:
                obj_box = prop_boxes[pid]
                
                # 1. 겹침 비율(IoU 유사) 계산 - 식사 모드에서 중요
                overlap = calculate_overlap_ratio(pet_box, obj_box)
                if overlap > max_overlap:
                    max_overlap = overlap
                    
                # 2. 중심 거리 계산 (Euclidean Distance) - 놀이/교감 모드에서 중요
                obj_cx = (obj_box[0] + obj_box[2]) / 2
                obj_cy = (obj_box[1] + obj_box[3]) / 2
                dist = np.sqrt((pet_cx - obj_cx)**2 + (pet_cy - obj_cy)**2)
                if dist < min_distance:
                    min_distance = dist
        
        # [모드별 판단 로직]
        if mode == "feeding":
            # [식사] 겹침(Overlap)이 발생해야 함 (입이나 몸이 그릇을 가림)
            # 기준: 물체가 10% 이상 반려동물 영역과 겹치거나, 거리가 매우 가까움
            if max_overlap > 0.1 or min_distance < 0.15: 
                is_interacting = True
            else:
                distance_msg = "그릇 가까이 가야 해요!"
                
        elif mode == "playing":
            # [놀이] 거리가 가까우면 됨 
            # 기준: 화면 너비의 25% 이내 접근
            if min_distance < 0.25:
                is_interacting = True
            else:
                distance_msg = "장난감과 너무 멀어요"
                
        elif mode == "interaction":
            # [교감] 사람(주인)과 가까워야 함
            if min_distance < 0.3:
                is_interacting = True
            else:
                distance_msg = "주인님과 더 가까이!"
    
    # 난이도 'hard'일 경우 기준 강화 (더 엄격한 판정)
    if difficulty == "hard" and is_interacting:
        if mode == "playing" and min_distance > 0.15:
            is_interacting = False
            distance_msg = "조금 더 가까이!"
        elif mode == "feeding" and max_overlap < 0.3:
            is_interacting = False
            distance_msg = "맛있게 먹는 모습 보여주세요!"

    # --- 최종 결과 구성 ---
    action_detected = None
    base_reward = {}
    bonus_points = 0
    message = mode_config["fail_msg"]
    feedback_message = mode_config["feedback_fail"]

    # 시각화용 데이터 (스켈레톤 등)
    normalized_keypoints = []

    if has_target:
        if is_interacting:
            # [성공 판정]
            message = mode_config["success_msg"]
            feedback_message = mode_config["feedback_success"]
            
            # 보상 설정 (스탯 증가량)
            if mode == "playing":
                action_detected = "playing_fetch"
                base_reward = {"stat_type": "strength", "value": 3}
                bonus_points = 2
            elif mode == "feeding":
                action_detected = "feeding"
                base_reward = {"stat_type": "health", "value": 3}
                bonus_points = 1
            elif mode == "interaction":
                action_detected = "interaction_owner"
                base_reward = {"stat_type": "happiness", "value": 4}
                bonus_points = 3
        else:
            # [실패 판정] 물건은 있으나 상호작용 안됨
            message = distance_msg if distance_msg else "더 적극적으로 움직여보세요!"
            feedback_message = "not_interacting"
            
        # [교감 모드 특수 처리] 사람 스켈레톤 추출하여 시각화 데이터로 반환
        if mode == "interaction" and (0 in prop_boxes):
            try:
                # 사람 전용 포즈 모델 실행
                results_pose = model_pose(frame_rgb, conf=0.45, classes=[0], verbose=False)
                if results_pose and results_pose[0].keypoints is not None:
                    if len(results_pose[0].keypoints.data) > 0:
                         kps = results_pose[0].keypoints.data[0].cpu().numpy()
                         for kp in kps:
                             # kp: [x, y, conf]
                             norm_x = float(kp[0]) / width
                             norm_y = float(kp[1]) / height
                             normalized_keypoints.append([norm_x, norm_y, float(kp[2])])
            except: pass

    else:
        # [실패 판정] 타겟 물건 자체가 없음
        pass

    return {
        "success": (action_detected is not None),
        "action_type": action_detected,
        "message": message,
        "feedback_message": feedback_message,
        "keypoints": normalized_keypoints,
        "skeleton_points": [],
        "bbox": pet_box,
        "width": width,
        "height": height,
        "conf_score": best_conf,
        "base_reward": base_reward,
        "bonus_points": bonus_points
    }
