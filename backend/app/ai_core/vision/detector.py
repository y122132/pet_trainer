import cv2
import numpy as np
import threading
from ultralytics import YOLO
from app.core.pet_behavior_config import PET_BEHAVIORS, DEFAULT_BEHAVIOR, DETECTION_SETTINGS 

# 전역 모델 변수 및 락 (Thread Safety)
model_pose = None
model_pet_pose = None # [Fix] Added missing global
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
            model_pose = YOLO("yolo11n-pose.pt", verbose=False) # 사람 포즈(주인용)
            # [Update] Allow using refined model
            model_pet_pose = YOLO("best_pet_pose_refine.pt", verbose=False) # 반려동물 포즈
            model_detect = YOLO("yolo11n.pt", verbose=False) # 사물 탐지(장난감, 밥그릇 등)
            print("YOLO models loaded. (로딩 완료)")
    return model_pose, model_pet_pose, model_detect

def process_frame(
    image_bytes: bytes, 
    mode: str = "playing", 
    target_class_id: int = 16, 
    difficulty: str = "easy",
    frame_index: int = 0,      # [New] 현재 프레임 번호
    process_interval: int = 1  # [New] 처리 간격 (1=매 프레임)
) -> dict:
    """
    프론트엔드에서 전송된 프레임을 분석하여 반려동물의 행동을 판단합니다.
    """
    
    # 1. 프레임 스킵 로직 (성능 최적화)
    # process_interval이 1보다 클 때만 스킵 로직 적용
    if process_interval > 1 and (frame_index % process_interval != 0):
        # 스킵된 경우 처리 안 함을 알림
        return {
            "success": False, 
            "skipped": True, 
            "message": f"Frame {frame_index} skipped for performance"
        }

    # 2. 모델 로드 (Thread-Safe)
    model_pose, model_pet_pose, model_detect = load_models()
    
    # 3. 바이너리 이미지 디코딩
    try:
        np_data = np.frombuffer(image_bytes, np.uint8)
        frame = cv2.imdecode(np_data, cv2.IMREAD_COLOR)
        
        if frame is None:
            return {"success": False, "message": "이미지 디코딩 실패"}
            
    except Exception as e:
        return {"success": False, "message": f"이미지 디코딩 에러: {str(e)}"}

    height, width, _ = frame.shape
    aspect_ratio = width / height
    orientation = "landscape" if width > height else "portrait"
    
    # [Optimization] 디스크 I/O (cv2.imwrite) 제거됨
    
    # frame_rgb 변환
    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    
    # ---------------------------------------------------------
    # 4. 반려동물 & 사물 탐지 (YOLO Object Detection)
    # ---------------------------------------------------------
    # ---------------------------------------------------------
    # 4. 모델 추론 (역할 분리)
    # ---------------------------------------------------------
    # Role 1: Pet Pose Model -> Detects Pet & Keypoints
    # Role 2: Object Model -> Detects Props (Bowl, Toy) ONLY
    # Role 3: Human Pose Model -> Detects Human & Keypoints

    INFERENCE_CONF = 0.25
    logic_conf_setting = DETECTION_SETTINGS["logic_conf"]
    # [Update] Raise LOGIC_CONF to 0.35 for Refined Model (Good Precision)
    LOGIC_CONF = 0.35 # logic_conf_setting.get(difficulty, logic_conf_setting["easy"])
    
    results_detect = None
    results_pet = None
    results_human = None

    try:
        with model_lock:
             # 1. Pet Pose (Pets)
             if model_pet_pose:
                 # [Tuning] Raise conf to 0.35 as model is improved (Refined)
                 results_pet = model_pet_pose(frame_rgb, conf=0.35, imgsz=640, verbose=False)
             
             # 2. Object Detection (Props)
             # User requested yolo11n to ONLY detect props. We can filter classes here or in loop.
             # Filtering in loop is safer as props might change.
             results_detect = model_detect(frame_rgb, conf=INFERENCE_CONF, imgsz=640, verbose=False)
             
             # 3. Human Pose (Owners)
             if model_pose:
                 # [Tuning] Lower conf to 0.25 to detect sitting humans (often lower score than standing)
                 results_human = model_pose(frame_rgb, conf=0.25, classes=[0], imgsz=640, verbose=False)
                 
    except Exception as e:
        return {"success": False, "message": f"AI 추론 중 오류: {str(e)}"}
    
    # --- 결과 파싱 ---
    detected_objects = []
    
    found_pet = False
    pet_box = [] 
    pet_keypoints = []
    pet_nose = None
    pet_paws = []
    
    best_conf = 0.0

    # Configs
    pet_config = PET_BEHAVIORS.get(target_class_id, DEFAULT_BEHAVIOR)
    if pet_config is None: pet_config = DEFAULT_BEHAVIOR
    mode_config = pet_config.get(mode, pet_config.get("playing", DEFAULT_BEHAVIOR["playing"]))
    target_props = mode_config["targets"]
    
    # -------------------------------------------------
    # A. 반려동물 처리 (From best_pet_pose)
    # -------------------------------------------------
    if results_pet and results_pet[0].boxes:
        # best_pet_pose classes: 0=Dog, 1=Cat (User Metadata)
        # target_class_id (COCO): 16=Dog, 15=Cat
        
        # Find best pet
        for i, box in enumerate(results_pet[0].boxes):
            cls_source = int(box.cls[0])
            conf = float(box.conf[0])
            
            # Map Source Class to COCO Class
            mapped_cls = -1
            if cls_source == 0: mapped_cls = 16 # Dog
            elif cls_source == 1: mapped_cls = 15 # Cat
            
            # Filter by Target (e.g. only dogs if target is dog)
            # Currently strict check
            if mapped_cls == target_class_id and conf >= LOGIC_CONF:
                if conf > best_conf:
                    best_conf = conf
                    found_pet = True
                    
                    x1, y1, x2, y2 = box.xyxyn[0].cpu().numpy()
                    nx1, ny1 = max(0.0, min(1.0, float(x1))), max(0.0, min(1.0, float(y1)))
                    nx2, ny2 = max(0.0, min(1.0, float(x2))), max(0.0, min(1.0, float(y2)))
                    pet_box = [nx1, ny1, nx2, ny2, float(conf), float(mapped_cls)]
                    
                    # Extract Keypoints for THIS pet
                    if results_pet[0].keypoints is not None and len(results_pet[0].keypoints.data) > i:
                        kps = results_pet[0].keypoints.data[i].cpu().numpy()
                        for k_idx, kp in enumerate(kps):
                            safe_w = max(1.0, float(width))
                            safe_h = max(1.0, float(height))
                            norm_x = float(kp[0]) / safe_w
                            norm_y = float(kp[1]) / safe_h
                            conf_k = float(kp[2])
                            pet_keypoints.append([norm_x, norm_y, conf_k])

                            if conf_k > 0.5:
                                if k_idx == 2: pet_nose = [norm_x, norm_y] 
                                if k_idx == 7: pet_paws.append([norm_x, norm_y]) 
                                if k_idx == 10: pet_paws.append([norm_x, norm_y])

        if found_pet:
            detected_objects.append(pet_box)

    # -------------------------------------------------
    # B. 타겟 물건 처리 (From yolo11n)
    # -------------------------------------------------
    props_detected = [] 
    prop_boxes = {} 
    max_conf_any = 0.0
    max_conf_cls = -1

    if results_detect and results_detect[0].boxes:
        for box in results_detect[0].boxes:
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])
            
             # Debug info
            if conf > max_conf_any:
                max_conf_any = conf
                max_conf_cls = cls_id
            
            # Skip Pet/Human classes in Object Detector to avoid duplicate/conflicting logic
            # [Fix] Also skip Class 77 (Teddy Bear) as it confuses users (Dog recognized as Teddy)
            if cls_id in [0, 15, 16, 77]: 
                continue

            # [Revert] Back to original logic requested by user
            if cls_id in target_props and conf >= LOGIC_CONF:
                x1, y1, x2, y2 = box.xyxyn[0].cpu().numpy()
                nx1, ny1 = max(0.0, min(1.0, float(x1))), max(0.0, min(1.0, float(y1)))
                nx2, ny2 = max(0.0, min(1.0, float(x2))), max(0.0, min(1.0, float(y2)))
                
                current_box = [nx1, ny1, nx2, ny2, float(conf), float(cls_id)]
                
                # Handling multiple props (Best conf)
                if cls_id not in prop_boxes or conf > (prop_boxes.get(cls_id, [])[4] if len(prop_boxes.get(cls_id, [])) > 4 else -1):
                        prop_boxes[cls_id] = current_box
                        if cls_id not in props_detected:
                            props_detected.append(cls_id)
                    
        # Register best props to detected_objects
        for pid in props_detected:
            if pid in prop_boxes:
                detected_objects.append(prop_boxes[pid])

    has_target_pre = any(p in props_detected for p in target_props)

    # -------------------------------------------------
    # C. 사람 처리 (From yolo11n-pose)
    # -------------------------------------------------
    human_keypoints = []
    
    if results_human and results_human[0].boxes:
         # [Fix] Add Human BBox to detected_objects/prop_boxes for Interaction Logic
         # Assume index 0 is main user
         box = results_human[0].boxes[0]
         x1, y1, x2, y2 = box.xyxyn[0].cpu().numpy()
         nx1, ny1 = max(0.0, min(1.0, float(x1))), max(0.0, min(1.0, float(y1)))
         nx2, ny2 = max(0.0, min(1.0, float(x2))), max(0.0, min(1.0, float(y2)))
         
         # Human is Class 0
         human_box = [nx1, ny1, nx2, ny2, float(box.conf[0]), 0.0]
         
         # Add to visually detected objects
         detected_objects.append(human_box)
         
         # Add to prop_boxes for distance calculation (interaction mode)
         prop_boxes[0] = human_box

    if results_human and results_human[0].keypoints is not None:
         if len(results_human[0].keypoints.data) > 0:
              # Assume index 0 is main user (single user support)
              kps = results_human[0].keypoints.data[0].cpu().numpy()
              for kp in kps:
                  safe_w = max(1.0, float(width))
                  safe_h = max(1.0, float(height))
                  norm_x = float(kp[0]) / safe_w
                  norm_y = float(kp[1]) / safe_h
                  human_keypoints.append([norm_x, norm_y, float(kp[2])])

    # 기본 리턴 구조
    base_response = {
        "success": False,
        "width": width,
        "height": height,
        "aspect_ratio": aspect_ratio,
        "orientation": orientation,
        "conf_score": best_conf,
        "debug_max_conf": max_conf_any,
        "debug_max_cls": max_conf_cls,
        "bbox": detected_objects,
        "is_specific_feedback": False,
        "message": "",
        "feedback_message": "",
        "keypoints": [],
        # [Fix] Include keypoints here so they are sent even if found_pet is False (Early Return)
        "pet_keypoints": pet_keypoints,
        "human_keypoints": human_keypoints,
        "skeleton_points": [] 
    }

    # [Case 1] 펫 미발견
    if not found_pet:
        # Debug Info for user
        raw_debug = f"(BestConf: {best_conf:.2f})"
        msg = f"반려동물 찾는 중... {raw_debug}"
        feedback_code = "pet_not_found"
        is_spec = False
        
        if mode == "interaction" and has_target_pre:
            msg = "주인님은 보이네요! 반려동물도 함께 보여주세요."
            feedback_code = "owner_found_no_pet"
            is_spec = True
        elif mode == "playing" and has_target_pre:
            msg = "장난감은 준비됐군요! 반려동물을 보여주세요."
            feedback_code = "toy_found_no_pet"
            is_spec = True
        
        base_response.update({
             "message": msg,
             "feedback_message": feedback_code,
             "is_specific_feedback": is_spec
        })
        return base_response

    # [Case 2] 펫 발견됨
    has_target = has_target_pre
    
    missing_prop_msg = ""
    if not has_target:
        if mode == "feeding": missing_prop_msg = "강아지는 보이는데, 밥그릇은 어디 있나요?"
        elif mode == "playing": missing_prop_msg = "강아지는 보이는데, 장난감(공)은 어디 있나요?"
        elif mode == "interaction": missing_prop_msg = "강아지는 보이는데, 주인님은 어디 계세요?"

    is_interacting = False
    distance_msg = ""
    
    MIN_DIST_SETTINGS = DETECTION_SETTINGS["min_distance"].get(mode, {"easy": 0.25, "hard": 0.15})
    MIN_DISTANCE = MIN_DIST_SETTINGS.get(difficulty, MIN_DIST_SETTINGS["easy"])
    MIN_DIST_SETTINGS = DETECTION_SETTINGS["min_distance"].get(mode, {"easy": 0.25, "hard": 0.15})
    MIN_DISTANCE = MIN_DIST_SETTINGS.get(difficulty, MIN_DIST_SETTINGS["easy"])
    
    if has_target:
        min_distance_val = 9999.0
        
        # [Upgraded Logic] Keypoint Priority
        src_points = []
        if mode == "feeding":
            if pet_nose: src_points.append(pet_nose)
            else: src_points.append([(pet_box[0]+pet_box[2])/2, (pet_box[1]+pet_box[3])/2])
        elif mode == "playing":
            if pet_nose: src_points.append(pet_nose)
            if pet_paws: src_points.extend(pet_paws)
            if not src_points and pet_box: src_points.append([(pet_box[0]+pet_box[2])/2, (pet_box[1]+pet_box[3])/2])
        elif mode == "interaction":
             if pet_nose: src_points.append(pet_nose)
             elif pet_box: src_points.append([(pet_box[0]+pet_box[2])/2, (pet_box[1]+pet_box[3])/2])

        for pid in target_props:
            if pid in prop_boxes:
                obj_box = prop_boxes[pid]
                obj_cx = (obj_box[0] + obj_box[2]) / 2
                obj_cy = (obj_box[1] + obj_box[3]) / 2
                
                for sp in src_points:
                    dist = np.sqrt((sp[0] - obj_cx)**2 + (sp[1] - obj_cy)**2)
                    if dist < min_distance_val: min_distance_val = dist
        
        if mode == "feeding":
            if min_distance_val < MIN_DISTANCE: is_interacting = True
            else: distance_msg = "그릇 가까이 가야 해요!"
        elif mode == "playing":
            if min_distance_val < MIN_DISTANCE: is_interacting = True
            else: distance_msg = "장난감과 너무 멀어요"
        elif mode == "interaction":
            if min_distance_val < MIN_DISTANCE: is_interacting = True
            else: distance_msg = "주인님과 더 가까이!"
    
    # --- 결과 구성 ---
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
            message = mode_config["success_msg"]
            feedback_message = mode_config["feedback_success"]
            is_specific_feedback = True
            
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

        # [Cleanup] Legacy Pose Logic was here (lines 370-401).
        # It caused duplicate inference and return flow issues.
        # It has been removed because 'Role 3' above now handles human pose.

    base_response.update({
        "success": (action_detected is not None),
        "action_type": action_detected,
        "message": message,
        "feedback_message": feedback_message,
        "pet_keypoints": pet_keypoints,
        "human_keypoints": human_keypoints,
        "bbox": detected_objects,
        "base_reward": base_reward,
        "bonus_points": bonus_points,
        "is_specific_feedback": is_specific_feedback
    })
    
    return base_response
