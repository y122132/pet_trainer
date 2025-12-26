import cv2
import numpy as np
import base64
from ultralytics import YOLO
from app.core.pet_behavior_config import PET_BEHAVIORS, DEFAULT_BEHAVIOR, DETECTION_SETTINGS 

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
    
    # [Improvement] Orientation & Aspect Ratio Calculation
    # OpenCV imdecode might ignore EXIF, so we explicitly report what we see.
    aspect_ratio = width / height
    orientation = "landscape" if width > height else "portrait"
    
    file_size_kb = len(image_bytes) / 1024
    print(f"[Detector] Input: {width}x{height} ({orientation}, AR: {aspect_ratio:.2f}), Size: {file_size_kb:.1f}KB", flush=True)

    # ---------------------------------------------------------
    # 2. 반려동물 & 사물 탐지 (YOLO Object Detection)
    # ---------------------------------------------------------
    
    # [Config] 임계값 로드
    INFERENCE_CONF = 0.25
    
    # 난이도 보정 (설정 파일 참조)
    logic_conf_setting = DETECTION_SETTINGS["logic_conf"]
    LOGIC_CONF = logic_conf_setting.get(difficulty, logic_conf_setting["easy"])
    
    # [Critical Fix] BGR -> RGB 변환
    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    
    # YOLO 추론
    results_detect = model_detect(frame_rgb, conf=INFERENCE_CONF, imgsz=640, verbose=False)
    
    found_pet = False
    pet_box = [] 
    best_conf = 0.0
    
    pet_config = PET_BEHAVIORS.get(target_class_id, DEFAULT_BEHAVIOR)
    mode_config = pet_config.get(mode, pet_config["playing"]) 
    target_props = mode_config["targets"]

    detected_objects = [] 
    props_detected = [] 
    prop_boxes = {} 
    
    if results_detect and results_detect[0].boxes:
        for box in results_detect[0].boxes:
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])
            
            # [Coordinate Normalization: Refined]
            # Use xyxyn (normalized 0-1) directly from YOLO to ensure accurate
            # letterbox padding correction (gain/pad calculation) matching the inference.
            # This accounts for the aspect ratio difference between input (WxH) and model (640x640).
            x1, y1, x2, y2 = box.xyxyn[0].cpu().numpy()
            
            # Clamp securely to avoid float precision overshooting
            nx1 = max(0.0, min(1.0, float(x1)))
            ny1 = max(0.0, min(1.0, float(y1)))
            nx2 = max(0.0, min(1.0, float(x2)))
            ny2 = max(0.0, min(1.0, float(y2)))
            
            current_box = [nx1, ny1, nx2, ny2]

            # [Visual] 시각화 리스트에 추가 (LOGIC_CONF 이상)
            if conf >= LOGIC_CONF:
                 if cls_id == target_class_id or cls_id in target_props:
                      detected_objects.append([nx1, ny1, nx2, ny2, float(conf), float(cls_id)])

            # A. 반려동물 찾기
            if cls_id == target_class_id and conf >= LOGIC_CONF:
                if conf > best_conf: # 가장 신뢰도 높은 객체 선택
                    best_conf = conf
                    found_pet = True
                    pet_box = [nx1, ny1, nx2, ny2, float(conf), float(cls_id)]
            
            # B. 타겟 물건 찾기
            if cls_id in target_props and conf >= LOGIC_CONF:
                if cls_id not in prop_boxes or conf > (prop_boxes.get(cls_id, [])[4] if len(prop_boxes.get(cls_id, [])) > 4 else -1):
                     prop_boxes[cls_id] = current_box + [conf]
                     if cls_id not in props_detected:
                         props_detected.append(cls_id)

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
    
    # 베스트 스코어 갱신
    if best_conf > max_conf_any:
        max_conf_any = best_conf
        max_conf_cls = target_class_id
    
    print(f"[Detector] All detections: {all_detections_summary}", flush=True)

    # 타겟(사람/장난감) 존재 여부 확인
    has_target_pre = any(p in props_detected for p in target_props)

    # [Case 1] 펫 미발견
    if not found_pet:
        msg = f"반려동물 찾는 중..."
        feedback_code = "pet_not_found"
        is_spec = False
        
        # 교감/놀이 모드에서 대상은 있는데 펫이 없는 경우
        if mode == "interaction" and has_target_pre:
            msg = "주인님은 보이네요! 반려동물도 함께 보여주세요."
            feedback_code = "owner_found_no_pet"
            is_spec = True
        elif mode == "playing" and has_target_pre:
            msg = "장난감은 준비됐군요! 반려동물을 보여주세요."
            feedback_code = "toy_found_no_pet"
            is_spec = True
        
        # 교감 모드에서 사람 스켈레톤 추출 (Visual Only)
        if mode == "interaction" and (0 in prop_boxes):
            # ... (아래 로직과 동일하게 스켈레톤 추출하여 리턴할 수도 있음. 여기선 생략하고 bbox만 리턴)
            pass

        return {
            "success": False,
            "message": msg, 
            "feedback_message": feedback_code,
            "keypoints": [],
            "width": width,
            "height": height,
            "aspect_ratio": aspect_ratio,   # [New]
            "orientation": orientation,     # [New]
            "conf_score": best_conf,
            "debug_max_conf": max_conf_any, 
            "debug_max_cls": max_conf_cls,
            "bbox": detected_objects,
            "is_specific_feedback": is_spec
        }

    # [Case 2] 펫 발견됨
    has_target = has_target_pre
    
    missing_prop_msg = ""
    if not has_target:
        if mode == "feeding":
            missing_prop_msg = "강아지는 보이는데, 밥그릇은 어디 있나요?"
        elif mode == "playing":
            missing_prop_msg = "강아지는 보이는데, 장난감(공)은 어디 있나요?"
        elif mode == "interaction":
            missing_prop_msg = "강아지는 보이는데, 주인님은 어디 계세요?"

    # 상호작용 판정
    is_interacting = False
    distance_msg = ""
    
    # [Config] 임계값 로드
    MIN_DIST_SETTINGS = DETECTION_SETTINGS["min_distance"].get(mode, {"easy": 0.25, "hard": 0.15})
    MIN_DISTANCE = MIN_DIST_SETTINGS.get(difficulty, MIN_DIST_SETTINGS["easy"])
    
    MAX_OVERLAP_SETTINGS = DETECTION_SETTINGS["max_overlap"]
    MAX_OVERLAP = MAX_OVERLAP_SETTINGS.get(difficulty, MAX_OVERLAP_SETTINGS["easy"])
    
    if has_target:
        max_overlap_val = 0.0
        min_distance_val = 9999.0
        
        pet_cx = (pet_box[0] + pet_box[2]) / 2
        pet_cy = (pet_box[1] + pet_box[3]) / 2

        for pid in target_props:
            if pid in prop_boxes:
                obj_box = prop_boxes[pid]
                
                # 1. Overlap (Feeding)
                overlap = calculate_overlap_ratio(pet_box, obj_box)
                if overlap > max_overlap_val: max_overlap_val = overlap
                    
                # 2. Distance (Playing/Interaction)
                obj_cx = (obj_box[0] + obj_box[2]) / 2
                obj_cy = (obj_box[1] + obj_box[3]) / 2
                dist = np.sqrt((pet_cx - obj_cx)**2 + (pet_cy - obj_cy)**2)
                if dist < min_distance_val: min_distance_val = dist
        
        # [모드별 판단]
        if mode == "feeding":
            # 식사: 겹치거나 매우 가까워야 함
            if max_overlap_val > MAX_OVERLAP or min_distance_val < MIN_DISTANCE: 
                is_interacting = True
            else:
                distance_msg = "그릇 가까이 가야 해요!"
                
        elif mode == "playing":
            # 놀이: 거리 기준
            if min_distance_val < MIN_DISTANCE:
                is_interacting = True
            else:
                distance_msg = "장난감과 너무 멀어요"
                
        elif mode == "interaction":
            # 교감: 거리 기준 (사람)
            if min_distance_val < MIN_DISTANCE:
                is_interacting = True
            else:
                distance_msg = "주인님과 더 가까이!"
    
    # --- 최종 결과 구성 ---
    action_detected = None
    base_reward = {}
    bonus_points = 0
    message = mode_config["fail_msg"]
    feedback_message = mode_config["feedback_fail"]
    is_specific_feedback = False

    if missing_prop_msg:
        message = missing_prop_msg
        feedback_message = "prop_missing"
        is_specific_feedback = True
    elif distance_msg:
        message = distance_msg
        feedback_message = "distance_fail"
        is_specific_feedback = True

    normalized_keypoints = []

    if has_target:
        if is_interacting:
            # [성공]
            message = mode_config["success_msg"]
            feedback_message = mode_config["feedback_success"]
            is_specific_feedback = True
            
            # 보상 로직 (기존 유지)
            if mode == "playing":
                action_detected = "playing_fetch"
                if np.random.rand() < 0.7: base_reward = {"stat_type": "strength", "value": 3}
                else: base_reward = {"stat_type": "agility", "value": 3}
                bonus_points = 2
            elif mode == "feeding":
                action_detected = "feeding"
                if np.random.rand() < 0.7: base_reward = {"stat_type": "health", "value": 3}
                else: base_reward = {"stat_type": "defense", "value": 3}
                bonus_points = 1
            elif mode == "interaction":
                action_detected = "interaction_owner"
                if np.random.rand() < 0.7: base_reward = {"stat_type": "happiness", "value": 4}
                else: base_reward = {"stat_type": "intelligence", "value": 3}
                bonus_points = 3
        else:
             message = distance_msg if distance_msg else "더 적극적으로 움직여보세요!"
             feedback_message = "not_interacting"
             is_specific_feedback = True

        # 사람 스켈레톤 (교감 모드)
        if mode == "interaction" and (0 in prop_boxes):
            try:
                # 사람 포즈 추론
                results_pose = model_pose(frame_rgb, conf=0.45, classes=[0], verbose=False)
                if results_pose and results_pose[0].keypoints is not None:
                    if len(results_pose[0].keypoints.data) > 0:
                         kps = results_pose[0].keypoints.data[0].cpu().numpy()
                         for kp in kps:
                             # kp: [x, y, conf]
                             safe_w = max(1.0, float(width))
                             safe_h = max(1.0, float(height))
                             norm_x = float(kp[0]) / safe_w
                             norm_y = float(kp[1]) / safe_h
                             normalized_keypoints.append([norm_x, norm_y, float(kp[2])])
            except: pass

    return {
        "success": (action_detected is not None),
        "action_type": action_detected,
        "message": message,
        "feedback_message": feedback_message,
        "keypoints": normalized_keypoints,
        "skeleton_points": [],
        "bbox": detected_objects,
        "width": width,
        "height": height,
        "aspect_ratio": aspect_ratio,   # [New]
        "orientation": orientation,     # [New]
        "conf_score": best_conf,
        "base_reward": base_reward,
        "bonus_points": bonus_points,
        "is_specific_feedback": is_specific_feedback
    }
