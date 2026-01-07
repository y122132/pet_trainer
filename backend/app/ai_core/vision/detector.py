import cv2
import numpy as np
import threading
import math
from ultralytics import YOLO
from app.core.pet_behavior_config import PET_BEHAVIORS, DEFAULT_BEHAVIOR, DETECTION_SETTINGS 

# 글로벌 모델 변수 및 락
model_pose = None
model_pet_pose = None 
model_detect = None
model_lock = threading.Lock()

def load_models():
    """
    YOLO AI 모델을 스레드 안전하게 로드합니다.
    """
    global model_pose, model_pet_pose, model_detect
    with model_lock:
        if model_pose is None:
            print("Loading YOLO models... (AI 모델 로딩 중)")
            try:
                # 1. 사람 포즈 (주인 인식)
                model_pose = YOLO("yolo11n-pose.pt", verbose=False) 
                # 2. 반려동물 포즈 (핵심 모델) - epoch50 적용
                model_pet_pose = YOLO("epoch70.pt", verbose=False)
                # 3. 사물 탐지 (장난감, 밥그릇 등)
                model_detect = YOLO("yolo11n.pt", verbose=False)
                print("YOLO models loaded successfully. (로딩 완료)")
            except Exception as e:
                print(f"CRITICAL ERROR: Failed to load models: {e}")
                raise e # 모델 로드 실패는 치명적임
    return model_pose, model_pet_pose, model_detect

def calculate_distance(p1, p2, aspect_ratio=1.0):
    """
    aspect_ratio (width / height)를 고려하여 정규 좌표계에서의 '시각적 거리'를 계산합니다.
    p1, p2: [x, y] (0.0 ~ 1.0)
    """
    dx = p1[0] - p2[0]
    dy = p1[1] - p2[1]
    
    # x축(가로)이 길면(aspect_ratio > 1), x축 변화량에 aspect_ratio를 곱해 
    # 정사각형 픽셀 기준 거리로 환산하거나, 반대로 y축을 보정할 수 있음.
    # 여기서는 '화면상 픽셀 거리' 개념으로 통일하기 위해 단순히 비례 보정.
    if aspect_ratio > 1.0:
        # 가로가 더 긴 경우 (Landscape)
        return math.sqrt((dx * aspect_ratio) ** 2 + dy ** 2)
    else:
        # 세로가 더 긴 경우 (Portrait)
        return math.sqrt(dx ** 2 + (dy / aspect_ratio) ** 2)

def process_frame(
    image_bytes: bytes, 
    mode: str = "playing", 
    target_class_id: int = 16, 
    difficulty: str = "easy",
    frame_index: int = 0,
    process_interval: int = 1
) -> dict:
    """
    프레임을 분석하여 반려동물과 타겟 물체의 상호작용을 판단합니다.
    """
    
    # 1. 성능 최적화: 프레임 스킵
    if process_interval > 1 and (frame_index % process_interval != 0):
        return {
            "success": False, 
            "skipped": True, 
            "message": f"Frame {frame_index} skipped"
        }

    # 3. 이미지 디코딩 및 모델 로드
    try:
        # 모델 로드 (가장 먼저 수행하여 실패 시 즉시 중단)
        model_pose, model_pet_pose, model_detect = load_models()

        np_data = np.frombuffer(image_bytes, np.uint8)
        frame = cv2.imdecode(np_data, cv2.IMREAD_COLOR)
        if frame is None:
            return {"success": False, "message": "이미지 디코딩 실패"}
    except Exception as e:
        return {"success": False, "message": f"처리 에러 (Decoding/Loading): {e}"}

    height, width, _ = frame.shape
    aspect_ratio = width / height if height > 0 else 1.0
    orientation = "landscape" if width > height else "portrait"
    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    
    # 4. 설정값
    INFERENCE_CONF = 0.25
    LOGIC_CONF = 0.35 # 정밀도를 위해 약간 높게 설정
    
    base_response = {
        "success": False,
        "width": width, "height": height,
        "aspect_ratio": aspect_ratio,
        "orientation": orientation,
        "bbox": [], "pet_keypoints": [], "human_keypoints": [],
        "message": "", "feedback_message": "", "is_specific_feedback": False,
        "base_reward": {}, "bonus_points": 0
    }

    results_detect = None
    results_pet = None
    results_human = None

    # 5. 모델 추론
    try:
        with model_lock:
            # A. 반려동물 포즈
            if model_pet_pose:
                results_pet = model_pet_pose(frame_rgb, conf=0.35, imgsz=640, verbose=False)
            # B. 사물 탐지
            if model_detect:
                results_detect = model_detect(frame_rgb, conf=INFERENCE_CONF, imgsz=640, verbose=False)
            # C. 사람 포즈
            if model_pose:
                results_human = model_pose(frame_rgb, conf=0.25, classes=[0], imgsz=640, verbose=False)
    except Exception as e:
        return {"success": False, "message": f"AI 추론 오류: {e}"}

    # 6. 결과 파싱 변수
    detected_objects = []
    prop_boxes = {} # class_id -> box
    found_pet = False
    pet_info = {"box": [], "keypoints": [], "nose": None, "paws": [], "conf": 0.0}

    # Config 로드
    pet_config = PET_BEHAVIORS.get(target_class_id, DEFAULT_BEHAVIOR)
    mode_config = pet_config.get(mode, DEFAULT_BEHAVIOR["playing"])
    target_props = mode_config["targets"]

    # ---------------------------------------------------------
    # A. 반려동물 처리 (Pet Pose)
    # ---------------------------------------------------------
    if results_pet and results_pet[0].boxes:
        best_conf = 0.0
        
        for i, box in enumerate(results_pet[0].boxes):
            cls_source = int(box.cls[0])
            conf = float(box.conf[0])
            
            # Class Mapping (Model -> COCO)
            mapped_cls = 16 if cls_source == 0 else (15 if cls_source == 1 else -1)
            
            # Target Check & Confidence Check
            if mapped_cls == target_class_id and conf >= LOGIC_CONF:
                if conf > best_conf:
                    best_conf = conf
                    found_pet = True
                    
                    # Box
                    x1, y1, x2, y2 = box.xyxyn[0].cpu().numpy()
                    nx1, ny1, nx2, ny2 = np.clip([x1, y1, x2, y2], 0.0, 1.0)
                    pet_box = [float(nx1), float(ny1), float(nx2), float(ny2), float(conf), float(mapped_cls)]
                    pet_info["box"] = pet_box
                    
                    # Keypoints
                    pet_info["keypoints"] = []
                    pet_info["paws"] = []
                    if results_pet[0].keypoints is not None and len(results_pet[0].keypoints.data) > i:
                        kps = results_pet[0].keypoints.data[i].cpu().numpy()
                        for k_idx, kp in enumerate(kps):
                            nx, ny, c = float(kp[0])/width, float(kp[1])/height, float(kp[2])
                            pet_info["keypoints"].append([nx, ny, c])
                            
                            if c > 0.5:
                                if k_idx == 0: pet_info["nose"] = [nx, ny] # COCO 0: Nose
                                if k_idx in [9, 10]: pet_info["paws"].append([nx, ny]) # COCO 9,10: Wrists (Front Paws)

        if found_pet:
            detected_objects.append(pet_info["box"])
            base_response["pet_keypoints"] = pet_info["keypoints"]
            base_response["conf_score"] = best_conf

    # ---------------------------------------------------------
    # B. 타겟 물건 처리 (Object Detection)
    # ---------------------------------------------------------
    detected_prop_ids = []
    if results_detect and results_detect[0].boxes:
        for box in results_detect[0].boxes:
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])
            
            # Skip conflict classes (Pet, Human, Bear)
            if cls_id in [0, 15, 16, 77]: continue 
            
            if cls_id in target_props and conf >= LOGIC_CONF:
                x1, y1, x2, y2 = box.xyxyn[0].cpu().numpy()
                nx1, ny1, nx2, ny2 = np.clip([x1, y1, x2, y2], 0.0, 1.0)
                current_box = [float(nx1), float(ny1), float(nx2), float(ny2), float(conf), float(cls_id)]
                
                # Keep best confidence per class
                if cls_id not in prop_boxes or conf > prop_boxes[cls_id][4]:
                    prop_boxes[cls_id] = current_box
                    if cls_id not in detected_prop_ids: detected_prop_ids.append(cls_id)

    # ---------------------------------------------------------
    # C. 사람 처리 (Human Pose)
    # ---------------------------------------------------------
    if results_human and results_human[0].boxes:
        # 가장 신뢰도 높은 사람 1명만 처리
        box = results_human[0].boxes[0]
        x1, y1, x2, y2 = box.xyxyn[0].cpu().numpy()
        nx1, ny1, nx2, ny2 = np.clip([x1, y1, x2, y2], 0.0, 1.0)
        human_box = [float(nx1), float(ny1), float(nx2), float(ny2), float(box.conf[0]), 0.0]
        
        detected_objects.append(human_box)
        prop_boxes[0] = human_box # 사람도 interaction 대상(Target ID 0)으로 취급
        
        if results_human[0].keypoints is not None:
            kps = results_human[0].keypoints.data[0].cpu().numpy()
            for kp in kps:
                nx, ny, c = float(kp[0])/width, float(kp[1])/height, float(kp[2])
                base_response["human_keypoints"].append([nx, ny, c])

    # Prop 결과 병합
    for pid in detected_prop_ids:
        detected_objects.append(prop_boxes[pid])
    
    base_response["bbox"] = detected_objects

    # ---------------------------------------------------------
    # 로직 판단 (Logic Decision)
    # ---------------------------------------------------------
    has_target = any(p in prop_boxes for p in target_props)
    
    # CASE 1: 펫 미발견
    if not found_pet:
        msg = "반려동물 찾는 중..."
        fb_code = "pet_not_found"
        
        if has_target:
            if mode == "interaction": msg, fb_code = "주인님은 보이네요! 펫도 보여주세요.", "owner_found_no_pet"
            elif mode == "playing": msg, fb_code = "장난감은 준비됐군요! 펫을 보여주세요.", "toy_found_no_pet"
            
        base_response.update({"message": msg, "feedback_message": fb_code, "is_specific_feedback": bool(has_target)})
        return base_response

    # CASE 2: 펫 발견 -> 상호작용 체크
    # 타겟 부재 체크
    if not has_target:
        missing_msg = {
            "feeding": "강아지는 보이는데, 밥그릇은 어디 있나요?",
            "playing": "강아지는 보이는데, 장난감(공)은 어디 있나요?",
            "interaction": "강아지는 보이는데, 주인님은 어디 계세요?"
        }.get(mode, "")
        
        base_response.update({
            "message": missing_msg,
            "feedback_message": "prop_missing",
            "is_specific_feedback": True
        })
        return base_response

    # 거리 계산
    min_dist_val = 9999.0
    
    # 거리 측정 기준점 (반려동물)
    src_points = []
    if pet_info["nose"]: src_points.append(pet_info["nose"])
    if mode == "playing" and pet_info["paws"]: src_points.extend(pet_info["paws"])
    # 없을 경우 bbox 중심
    if not src_points and pet_info["box"]:
        bx = pet_info["box"]
        src_points.append([(bx[0]+bx[2])/2, (bx[1]+bx[3])/2])

    # 타겟과의 거리 측정
    for pid in target_props:
        if pid in prop_boxes:
            target_box = prop_boxes[pid]
            target_cx = (target_box[0] + target_box[2]) / 2
            target_cy = (target_box[1] + target_box[3]) / 2
            
            for sp in src_points:
                # [개선된 거리 계산] aspect_ratio 반영
                dist = calculate_distance(sp, [target_cx, target_cy], aspect_ratio)
                if dist < min_dist_val: min_dist_val = dist

    # 거리 임계값 (설정값)
    MIN_DIST_SETTINGS = DETECTION_SETTINGS["min_distance"].get(mode, {"easy": 0.25, "hard": 0.15})
    MIN_DISTANCE = MIN_DIST_SETTINGS.get(difficulty, MIN_DIST_SETTINGS["easy"])
    
    # 상호작용 판정
    is_interacting = (min_dist_val < MIN_DISTANCE)
    
    if is_interacting:
        # 성공!
        msg, fb_code = mode_config["success_msg"], mode_config["feedback_success"]
        action_type = None
        
        if mode == "playing":
            action_type = "playing_fetch"
            base_response["base_reward"] = {"stat_type": "strength", "value": 3} if np.random.rand() < 0.7 else {"stat_type": "agility", "value": 3}
            base_response["bonus_points"] = 2
        elif mode == "feeding":
            action_type = "feeding"
            base_response["base_reward"] = {"stat_type": "health", "value": 3} if np.random.rand() < 0.7 else {"stat_type": "defense", "value": 3}
            base_response["bonus_points"] = 1
        elif mode == "interaction":
            action_type = "interaction_owner"
            base_response["base_reward"] = {"stat_type": "happiness", "value": 4} if np.random.rand() < 0.7 else {"stat_type": "intelligence", "value": 3}
            base_response["bonus_points"] = 3
            
        base_response.update({
            "success": True,
            "action_type": action_type,
            "message": msg,
            "feedback_message": fb_code,
            "is_specific_feedback": True
        })
    else:
        # 실패 (거리 부족)
        fail_msgs = {
            "feeding": "그릇 가까이 가야 해요!",
            "playing": "장난감과 너무 멀어요",
            "interaction": "주인님과 더 가까이!"
        }
        msg = fail_msgs.get(mode, "더 적극적으로 움직여보세요!")
        base_response.update({
            "success": False,
            "message": msg,
            "feedback_message": "distance_fail", # or "not_interacting"
            "is_specific_feedback": True
        })

    return base_response
