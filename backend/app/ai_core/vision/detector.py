import cv2
import numpy as np
import threading
from ultralytics import YOLO
from app.core.pet_behavior_config import PET_BEHAVIORS, DEFAULT_BEHAVIOR, DETECTION_SETTINGS 

# 전역 모델 변수 및 락 (Thread Safety)
model_pose = None
model_detect = None
model_lock = threading.Lock()

def load_models():
    """
    YOLO AI 모델을 스레드 안전하게 로드합니다.
    """
    global model_pose, model_detect
    with model_lock:
        if model_pose is None:
            print("Loading YOLO models... (AI 모델 로딩 중)")
            model_pose = YOLO("yolo11n-pose.pt", verbose=False)
            # model_detect = YOLO("yolo11n.pt", verbose=False) 
            model_detect = YOLO("yolo11n.pt", verbose=False)
            print("YOLO models loaded. (로딩 완료)")
    return model_pose, model_detect

def calculate_iou(box1, box2):
    """
    두 박스 간의 IoU (Intersection over Union)를 계산합니다.
    box: [x1, y1, x2, y2] (정규화된 좌표)
    """
    xA = max(box1[0], box2[0])
    yA = max(box1[1], box2[1])
    xB = min(box1[2], box2[2])
    yB = min(box1[3], box2[3])

    interArea = max(0, xB - xA) * max(0, yB - yA)
    if interArea == 0: return 0.0

    box1Area = (box1[2] - box1[0]) * (box1[3] - box1[1])
    box2Area = (box2[2] - box2[0]) * (box2[3] - box2[1])

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
    return interArea / objArea

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
    model_pose, model_detect = load_models()
    
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
    INFERENCE_CONF = 0.25
    logic_conf_setting = DETECTION_SETTINGS["logic_conf"]
    LOGIC_CONF = logic_conf_setting.get(difficulty, logic_conf_setting["easy"])
    
    results_detect = None
    try:
        # [Optimization] Thread-Safe Inference
        with model_lock:
            results_detect = model_detect(frame_rgb, conf=INFERENCE_CONF, imgsz=640, verbose=False)
    except Exception as e:
        return {"success": False, "message": f"객체 감지(YOLO) 중 오류 발생: {str(e)}"}
    
    found_pet = False
    pet_box = [] 
    best_conf = 0.0
    
    pet_config = PET_BEHAVIORS.get(target_class_id, DEFAULT_BEHAVIOR)
    # 기본값 처리 강화
    if pet_config is None: pet_config = DEFAULT_BEHAVIOR
    
    mode_config = pet_config.get(mode, pet_config.get("playing", DEFAULT_BEHAVIOR["playing"]))
    target_props = mode_config["targets"]

    detected_objects = [] 
    props_detected = [] 
    prop_boxes = {} 
    
    max_conf_any = 0.0
    max_conf_cls = -1

    if results_detect and results_detect[0].boxes:
        for box in results_detect[0].boxes:
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])
            
            # [Debug Info]
            if conf > max_conf_any:
                max_conf_any = conf
                max_conf_cls = cls_id
            
            x1, y1, x2, y2 = box.xyxyn[0].cpu().numpy()
            nx1 = max(0.0, min(1.0, float(x1)))
            ny1 = max(0.0, min(1.0, float(y1)))
            nx2 = max(0.0, min(1.0, float(x2)))
            ny2 = max(0.0, min(1.0, float(y2)))
            
            current_box = [nx1, ny1, nx2, ny2]

            # [Visual]
            if conf >= LOGIC_CONF:
                 if cls_id == target_class_id or cls_id in target_props:
                      detected_objects.append([nx1, ny1, nx2, ny2, float(conf), float(cls_id)])

            # A. 반려동물 찾기
            if cls_id == target_class_id and conf >= LOGIC_CONF:
                if conf > best_conf:
                    best_conf = conf
                    found_pet = True
                    pet_box = [nx1, ny1, nx2, ny2, float(conf), float(cls_id)]
            
            # B. 타겟 물건 찾기
            if cls_id in target_props and conf >= LOGIC_CONF:
                # 같은 물체가 여러 개면 더 확실한 것 우선
                if cls_id not in prop_boxes or conf > (prop_boxes.get(cls_id, [])[4] if len(prop_boxes.get(cls_id, [])) > 4 else -1):
                     prop_boxes[cls_id] = current_box + [conf]
                     if cls_id not in props_detected:
                         props_detected.append(cls_id)
    
    # 디버그 프린트 제거 (혹은 주석 처리)
    # print(f"[Detector] ...")
    
    has_target_pre = any(p in props_detected for p in target_props)

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
        "skeleton_points": [] 
    }

    # [Case 1] 펫 미발견
    if not found_pet:
        msg = f"반려동물 찾는 중..."
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
                
                # 1. Overlap
                overlap = calculate_overlap_ratio(pet_box, obj_box)
                if overlap > max_overlap_val: max_overlap_val = overlap
                    
                # 2. Distance
                obj_cx = (obj_box[0] + obj_box[2]) / 2
                obj_cy = (obj_box[1] + obj_box[3]) / 2
                dist = np.sqrt((pet_cx - obj_cx)**2 + (pet_cy - obj_cy)**2)
                if dist < min_distance_val: min_distance_val = dist
        
        # [모드별 판단]
        if mode == "feeding":
            if max_overlap_val > MAX_OVERLAP or min_distance_val < MIN_DISTANCE: 
                is_interacting = True
            else:
                distance_msg = "그릇 가까이 가야 해요!"
        elif mode == "playing":
            if min_distance_val < MIN_DISTANCE:
                is_interacting = True
            else:
                distance_msg = "장난감과 너무 멀어요"
        elif mode == "interaction":
            if min_distance_val < MIN_DISTANCE:
                is_interacting = True
            else:
                distance_msg = "주인님과 더 가까이!"
    
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

        # 사람 포즈 추론 (교감 모드)
        if mode == "interaction" and (0 in prop_boxes):
            try:
                # [Optimization] Thread-Safe Pose Inference
                results_pose = None
                with model_lock:
                    results_pose = model_pose(frame_rgb, conf=0.45, classes=[0], verbose=False)
                
                # [Error Handling] 결과 검증 및 피드백
                if not results_pose or results_pose[0].keypoints is None:
                     # 중요: 에러를 발생시켜 catch 블록에서 피드백 리턴
                     raise ValueError("No pose keypoints data")
                
                if len(results_pose[0].keypoints.data) > 0:
                     kps = results_pose[0].keypoints.data[0].cpu().numpy()
                     for kp in kps:
                         safe_w = max(1.0, float(width))
                         safe_h = max(1.0, float(height))
                         norm_x = float(kp[0]) / safe_w
                         norm_y = float(kp[1]) / safe_h
                         normalized_keypoints.append([norm_x, norm_y, float(kp[2])])
            
            except Exception as e:
                # [Optimization] 포즈 추정 실패 시 사용자 피드백 제공
                # 기존 로직을 방해하지 않으면서 피드백만 교체
                print(f"[Detector] Pose Error: {str(e)}")
                return {
                    "success": False,
                    "message": "반려동물의 자세를 인식할 수 없습니다.", # 구체적인 피드백
                    "feedback_message": "pose_error",
                    "width": width, "height": height, "bbox": detected_objects # 화면이 멈추지 않게 최소 데이터 리턴
                }

    base_response.update({
        "success": (action_detected is not None),
        "action_type": action_detected,
        "message": message,
        "feedback_message": feedback_message,
        "keypoints": normalized_keypoints,
        "bbox": detected_objects,
        "base_reward": base_reward,
        "bonus_points": bonus_points,
        "is_specific_feedback": is_specific_feedback
    })
    
    return base_response
