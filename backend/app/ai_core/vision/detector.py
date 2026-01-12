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

# [Optimization] Granular Locks for Scalability
# 개별 모델 락을 사용하여, 서로 다른 모델을 사용하는 요청들이 병렬로 처리될 수 있게 함
# 예: A유저(사물탐지 중)가 B유저(사람인식 중)를 차단하지 않음
load_lock = threading.Lock()
lock_pose = threading.Lock()
lock_pet = threading.Lock()
lock_detect = threading.Lock()

def load_models():
    """
    YOLO AI 모델을 스레드 안전하게 로드합니다.
    """
    global model_pose, model_pet_pose, model_detect
    
    # [Optimization] Double-Checked Locking
    # 이미 로드되었다면 락 획득 시도 없이 즉시 반환 (성능 향상)
    if model_pose and model_pet_pose and model_detect:
        return model_pose, model_pet_pose, model_detect

    with load_lock:
        # 락 진입 후 다시 체크 (동시 진입 방지)
        if model_pose is None or model_pet_pose is None or model_detect is None:
            print("Loading YOLO models... (AI 모델 로딩 중)")
            try:
                # 1. 사람 포즈 (주인 인식)
                if model_pose is None:
                    model_pose = YOLO("yolo11n-pose.pt", verbose=False) 
                # 2. 반려동물 포즈 (핵심 모델) - pet_pose_best.pt 적용
                if model_pet_pose is None:
                    model_pet_pose = YOLO("best.pt", verbose=False)
                # 3. 사물 탐지 (장난감, 밥그릇 등)
                if model_detect is None:
                    model_detect = YOLO("yolo11n.pt", verbose=False)
                print("YOLO models loaded successfully. (로딩 완료)")
            except Exception as e:
                print(f"CRITICAL ERROR: Failed to load models: {e}")
                # 로딩 실패 시 부분적으로 로드된 모델도 초기화하여 재시도 유도
                model_pose = None
                model_pet_pose = None
                model_detect = None
                raise e # 모델 로드 실패는 치명적임
    return model_pose, model_pet_pose, model_detect

def calculate_squared_distance(p1, p2, x_scale, y_scale):
    """
    aspect_ratio를 고려한 '시각적 거리의 제곱'을 계산합니다.
    (Optimization: Scale Factor Pre-calculation 적용)
    """
    dx = (p1[0] - p2[0]) * x_scale
    dy = (p1[1] - p2[1]) * y_scale
    return dx*dx + dy*dy

# [Optimization] Temporal Aggregation Function
def apply_temporal_smoothing(current_box, current_cls, vision_state):
    if not vision_state: return current_box, current_cls
    
    # 1. Initialize History Deques
    if "history_boxes" not in vision_state: vision_state["history_boxes"] = []
    if "history_classes" not in vision_state: vision_state["history_classes"] = []
    if "ema_box" not in vision_state: vision_state["ema_box"] = None
    
    # 2. Class Voting (Consensus)
    history_classes = vision_state["history_classes"]
    history_classes.append(current_cls)
    if len(history_classes) > 5: history_classes.pop(0)
    
    # Most frequent class
    from collections import Counter
    most_common = Counter(history_classes).most_common(1)
    consensus_cls = most_common[0][0] if most_common else current_cls
    
    # 3. EMA Smoothing
    x1, y1, x2, y2, conf, _ = current_box
    current_coords = np.array([x1, y1, x2, y2])
    
    ema_box = vision_state.get("ema_box")
    if ema_box is None:
        ema_box = current_coords
    else:
        alpha = 0.6 # Smoothing factor (0.6 = new 60%, old 40%)
        ema_box = alpha * current_coords + (1 - alpha) * ema_box
        
    vision_state["ema_box"] = ema_box
    
    # Return smoothed detection
    # [Fix] Explicit cast to native float for JSON serialization (Numpy types crash json.dumps)
    smoothed_box = [float(ema_box[0]), float(ema_box[1]), float(ema_box[2]), float(ema_box[3]), float(conf), float(consensus_cls)]
    return smoothed_box, consensus_cls

def process_frame(
    image_bytes,  # [Modified] bytes or np.ndarray 
    mode: str = "playing", 
    target_class_id: int = 16, 
    difficulty: str = "easy",
    frame_index: int = 0,
    process_interval: int = 1,
    frame_id: int = -1,
    vision_state: dict = None # [NEW] Anti-Flickering State
) -> dict:
    """
    프레임을 분석하여 반려동물과 타겟 물체의 상호작용을 판단합니다.
    """
    
    # 1. 성능 최적화: 프레임 스킵
    if process_interval > 1 and (frame_index % process_interval != 0):
        # [Optimization] Zero-Order Hold (결과 재사용)
        # 이전 결과가 있으면 그대로 반환하여 클라이언트 화면이 부드럽게 이어지게 함.
        if vision_state and vision_state.get("last_response"):
            cached = vision_state["last_response"].copy() # Shallow copy
            cached["frame_id"] = frame_id # ID는 최신으로 동기화
            cached["skipped"] = True      # 디버깅용 마킹 (실제론 처리 안함)
            return cached
            
        return {
            "success": False, 
            "skipped": True, 
            "message": f"Frame {frame_index} skipped",
            "frame_id": frame_id
        }

    # 3. 이미지 디코딩 및 모델 로드
    try:
        # 모델 로드 (가장 먼저 수행하여 실패 시 즉시 중단)
        model_pose, model_pet_pose, model_detect = load_models()

        # [Modified] Support Raw Input (No Decoding needed for local test)
        if isinstance(image_bytes, bytes):
            np_data = np.frombuffer(image_bytes, np.uint8)
            frame = cv2.imdecode(np_data, cv2.IMREAD_COLOR)
        else:
            frame = image_bytes
        if frame is None:
            return {"success": False, "message": "이미지 디코딩 실패", "frame_id": frame_id}
    except Exception as e:
        print(f"[Detector Error] Decoding/Loading failed: {e}")
        return {"success": False, "message": f"처리 에러 (Decoding/Loading): {e}", "frame_id": frame_id}

    height, width, _ = frame.shape
    aspect_ratio = width / height if height > 0 else 1.0
    orientation = "landscape" if width > height else "portrait"
    
    # [Optimization] Distance Scale Pre-calculation
    # 반복문 내에서 조건문을 없애기 위해 미리 스케일 팩터 계산
    if aspect_ratio > 1.0:
        x_scale, y_scale = aspect_ratio, 1.0
    else:
        x_scale, y_scale = 1.0, 1.0 / aspect_ratio
    
    # 4. 설정값
    # [Anti-Flickering] 기본 추론은 넓게(0.40), 로직에서 필터링
    INFERENCE_LOW_CONF = 0.30 # [Tuning] Stricter noise filtering
    LOGIC_HIGH_CONF = 0.30 # [Tuning] Strict initial check
    LOGIC_LOW_CONF = 0.25  # [Tuning] Maintenance threshold
    
    # State 조회
    last_pet_exists = False
    if vision_state and vision_state.get("is_tracking", False):
        last_pet_exists = True
        
    LOGIC_CONF = LOGIC_LOW_CONF if last_pet_exists else LOGIC_HIGH_CONF
    
    base_response = {
        "success": False,
        "width": width, "height": height,
        "aspect_ratio": aspect_ratio,
        "orientation": orientation,
        "bbox": [], "pet_keypoints": [], "human_keypoints": [],
        "message": "", "feedback_message": "", "is_specific_feedback": False,
        "base_reward": {}, "bonus_points": 0,
        "frame_id": frame_id 
    }

    results_detect = None
    results_pet = None
    results_human = None

    # 5. 모델 추론
    try:
        # [Optimization] Granular Locking
        # 하나의 거대한 Lock 대신, 각 모델별로 Lock을 걸어 병렬성 확보
        
        # A. 반려동물 포즈 (Always Run)
        if model_pet_pose:
            with lock_pet:
                # [Fix] Use 'frame' (BGR) instead of 'frame_rgb' because Ultralytics assumes BGR for numpy inputs
                results_pet = model_pet_pose(frame, conf=INFERENCE_LOW_CONF, imgsz=1280, verbose=False)
        
        # B. 사물 탐지 (Run only if NOT interaction mode)
        if model_detect and mode != "interaction":
            with lock_detect:
                results_detect = model_detect(frame, conf=0.25, imgsz=640, verbose=False)
        
        # C. 사람 포즈 (Run only if interaction mode)
        if model_pose and mode == "interaction":
            with lock_pose:
                results_human = model_pose(frame, conf=0.25, classes=[0], imgsz=640, verbose=False)
                
    except Exception as e:
        print(f"[Detector Error] Inference failed: {e}")
        import traceback
        traceback.print_exc()
        return {"success": False, "message": f"AI 추론 오류: {e}", "frame_id": frame_id}

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
        # [Fix] Name-Based Mapping applied
        names = results_pet[0].names
        
        for i, box in enumerate(results_pet[0].boxes):
            cls_source = int(box.cls[0])
            conf = float(box.conf[0])
            
            # [Fix] Class Mapping (ID-Based for epoch50.pt)
            # 매핑 규칙: 0(Dog)->16, 1(Cat)->15, 2(Bird)->14
            if cls_source == 0: mapped_cls = 16   # Dog
            elif cls_source == 1: mapped_cls = 15 # Cat
            elif cls_source == 2: mapped_cls = 14 # Bird
            else:
                # Fallback to name-based if ID doesn't match known custom classes
                class_name = names.get(cls_source, "").lower()
                if "dog" in class_name: mapped_cls = 16
                elif "cat" in class_name: mapped_cls = 15
                elif "bird" in class_name: mapped_cls = 14
                else: mapped_cls = -1
            
            # Target Check & Confidence Check
            # [Anti-Flickering] Use dynamic LOGIC_CONF (0.35 or 0.20)
            if mapped_cls in [14, 15, 16] and conf >= LOGIC_CONF:
                # 1. BBox Construction
                x1, y1, x2, y2 = box.xyxyn[0].cpu().numpy()
                nx1, ny1, nx2, ny2 = np.clip([x1, y1, x2, y2], 0.0, 1.0)
                current_pet_box = [float(nx1), float(ny1), float(nx2), float(ny2), float(conf), float(mapped_cls)]
                
                # Add to total detections (for visualization of ALL pets)
                detected_objects.append(current_pet_box)

                # 2. Keypoint Logic (Select PRIMARY pet for interaction)
                # If target_class_id is -1, we pick the highest confidence pet automatically
                is_target = False
                if target_class_id == -1:
                    if conf > best_conf: is_target = True
                elif mapped_cls == target_class_id:
                    if conf > best_conf: is_target = True
                
                if is_target:
                    best_conf = conf
                        
                    # [NEW] Temporal Smoothing
                    if vision_state:
                         smoothed_box, smoothed_cls = apply_temporal_smoothing(current_pet_box, mapped_cls, vision_state)
                         pet_info["box"] = smoothed_box
                         mapped_cls = smoothed_cls # Update class for logic
                         # Re-add smoothed box to detected_objects for visualization (replacing the raw one is hard, so we just append. 
                         # Actually logic below adds it. But detected_objects has raw. 
                         # Ideally we want visualization to show the smoothed output for the target.
                         # Simple hack: detected_objects.append(smoothed_box) allows visualizing both or just smoothed if we filter.
                         # For now, let's just use it for logic.
                    
                    found_pet = True
                    if "box" not in pet_info or len(pet_info["box"]) == 0: pet_info["box"] = current_pet_box # Fallback

                    # [Dynamic Config Update] Auto-detect mode (-1)
                    # If we found a specific pet (e.g. Bird), switch to its specific config
                    if target_class_id == -1:
                         real_cls_id = int(mapped_cls)
                         if real_cls_id in PET_BEHAVIORS:
                             pet_config = PET_BEHAVIORS[real_cls_id]
                             # Re-load mode settings
                             mode_config = pet_config.get(mode, DEFAULT_BEHAVIOR["playing"])
                             target_props = mode_config["targets"]

                    # Keypoints
                    pet_info["keypoints"] = []
                    pet_info["paws"] = []
                    
                    if results_pet[0].keypoints is not None and len(results_pet[0].keypoints.data) > i:
                        kps = results_pet[0].keypoints.data[i].cpu().numpy()
                        for k_idx, kp in enumerate(kps):
                            nx, ny, c = float(kp[0])/width, float(kp[1])/height, float(kp[2])
                            pet_info["keypoints"].append([nx, ny, c])
                            
                            if c > 0.30: # [Tuning] Raised to 0.30 as requested
                                if k_idx == 0: pet_info["nose"] = [nx, ny] # COCO 0: Nose
                                if k_idx in [9, 10]: pet_info["paws"].append([nx, ny]) # COCO 9,10: Wrists (Front Paws)
        
        # [Anti-Flickering] Persistence Logic (단기 기억)
        if found_pet:
            # 성공 -> 상태 업데이트
            if vision_state is not None:
                vision_state["last_pet_box"] = pet_info.copy() # 전체 정보 저장
                vision_state["missing_count"] = 0
                vision_state["is_tracking"] = True
        
        elif vision_state is not None and vision_state.get("is_tracking", False):
            # 실패했지만 추적 중이었음 -> 유예 기간 체크
            MAX_MISSING = 5 # 약 0.15~0.2초
            if vision_state["missing_count"] < MAX_MISSING:
                # [유령 복구] 이전 정보 사용
                last_info = vision_state.get("last_pet_box")
                if last_info:
                    pet_info = last_info # 복구
                    found_pet = True
                    
                    # [Fix] Anti-Flickering: Recover Target Props
                    # 상태 복구 시, 해당 펫에 맞는 타겟(장난감 등) 목록도 다시 로드해야 함
                    if target_class_id == -1 and len(pet_info["box"]) > 5:
                        recovered_cls = int(pet_info["box"][5])
                        if recovered_cls in PET_BEHAVIORS:
                             pet_config = PET_BEHAVIORS[recovered_cls]
                             mode_config = pet_config.get(mode, DEFAULT_BEHAVIOR["playing"])
                             target_props = mode_config["targets"]
                    # [Fix] 잔상 복구 시 신뢰도 점수도 복구
                    if len(pet_info["box"]) > 4:
                        best_conf = pet_info["box"][4]
                        # 복구된 박스도 시각화 목록에 추가 (유령 효과)
                        detected_objects.append(pet_info["box"])
                    
                    vision_state["missing_count"] += 1
                    # Note: keypoints 등도 last_info에 포함되어 있음
                    # 시각적 구분을 위해 conf를 살짝 낮출 수도 있음 (선택사항)
            else:
                # 유예 기간 초과 -> 완전 소실
                vision_state["is_tracking"] = False
                vision_state["last_pet_box"] = None

        if found_pet:
            # Note: pet_info["box"] is already added to detected_objects inside the loop or recovery block
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
            
            # Skip conflict classes (Person 0, Bird 14, Cat 15, Dog 16)
            # Note: 77(Teddy Bear) is a valid target prop, so DO NOT exclude it.
            if cls_id in [0, 14, 15, 16]: continue 
            
            if cls_id in target_props and conf >= 0.35: # 물체는 0.35 고정 (변경 없음)
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

    # [NEW] Rich Detections (Label & Color included)
    # This allows clients to simply render what we send without maintaining their own mappings
    rich_detections = []
    
    # Define mappings (BGR for OpenCV compatibility)
    # Dog(16): Orange, Cat(15): Yellow-Orange, Bird(14): Cyan, Human(0): Green
    CLASS_META = {
        16: {"label": "Dog", "color": (0, 165, 255)},
        15: {"label": "Cat", "color": (0, 128, 255)},
        14: {"label": "Bird", "color": (255, 255, 0)},
        0:  {"label": "Human", "color": (0, 255, 0)},
    }
    
    for obj in detected_objects:
        # obj format: [x1, y1, x2, y2, conf, cls_id]
        cls_id = int(obj[5])
        conf = float(obj[4])
        meta = CLASS_META.get(cls_id, {"label": "Unknown", "color": (255, 0, 0)})
        
        rich_detections.append({
            "box": obj[:4], # [x1, y1, x2, y2]
            "class_id": cls_id,
            "conf": conf,
            "label": meta["label"],
            "color": meta["color"]
        })
        
    base_response["detections"] = rich_detections

    # ---------------------------------------------------------
    # 로직 판단 (Logic Decision) - [Refactored]
    # ---------------------------------------------------------
    return process_logic_only(
        detected_objects=detected_objects,
        mode=mode,
        target_class_id=target_class_id,
        difficulty=difficulty,
        vision_state=vision_state,
        base_response=base_response, # Passes keypoints, width/height etc
        pet_info_override=pet_info # Pass the pet_info found during inference (smoothing applied)
    )

def process_logic_only(
    detected_objects: list,
    mode: str,
    target_class_id: int,
    difficulty: str,
    vision_state: dict,
    base_response: dict = None,
    pet_info_override: dict = None
) -> dict:
    """
    Edge AI 또는 Server AI의 감지 결과(BBox)를 바탕으로 게임 로직을 수행합니다.
    """
    if base_response is None:
        base_response = { 
            "success": False, "message": "", "feedback_message": "", 
            "is_specific_feedback": False, "base_reward": {}, "bonus_points": 0,
            "bbox": detected_objects 
        }

    # Config 로드
    pet_config = PET_BEHAVIORS.get(target_class_id, DEFAULT_BEHAVIOR)
    mode_config = pet_config.get(mode, DEFAULT_BEHAVIOR["playing"])
    target_props = mode_config["targets"]
    
    # [Optimization] Scale Factors (Approximation if width/height missing)
    width = base_response.get("width", 640)
    height = base_response.get("height", 640)
    aspect_ratio = width / height if height > 0 else 1.0
    
    if aspect_ratio > 1.0: x_scale, y_scale = aspect_ratio, 1.0
    else: x_scale, y_scale = 1.0, 1.0 / aspect_ratio

    # 1. Parse Detections
    prop_boxes = {}
    found_pet = False
    pet_info = {"box": [], "keypoints": [], "nose": None, "paws": [], "conf": 0.0}
    
    # If passed from process_frame, use the already smoothed info
    if pet_info_override and pet_info_override.get("box"):
        pet_info = pet_info_override
        found_pet = True
        # prop_boxes still need to be filled from detected_objects for non-pet items
    
    # Re-scan detected_objects to fill prop_boxes and find pet if missing
    best_pet_conf = 0.0
    
    for obj in detected_objects:
        # obj: [x1, y1, x2, y2, conf, cls_id]
        if len(obj) < 6: continue
        
        box = obj[:4]
        conf = float(obj[4])
        cls_id = int(obj[5])
        
        # Pet Check (Dog 16, Cat 15, Bird 14)
        if cls_id in [14, 15, 16]:
            if not found_pet: # If not already provided by override
                is_target = False
                if target_class_id == -1: 
                    if conf > best_pet_conf: is_target = True
                elif cls_id == target_class_id:
                    if conf > best_pet_conf: is_target = True
                
                if is_target:
                    best_pet_conf = conf
                    
                    # [NEW] Temporal Smoothing Logic Reuse
                    if vision_state:
                         smoothed_box, smoothed_cls = apply_temporal_smoothing(obj, cls_id, vision_state)
                         pet_info["box"] = smoothed_box
                         # If consensus class changes, we should technically update logic, 
                         # but for simplicity we rely on current box geometry primarily.
                         # If smooth_cls changes Pet Type (Dog->Cat), that's rare.
                    else:
                         pet_info["box"] = obj

                    pet_info["conf"] = conf
                    found_pet = True

                    # [Dynamic Config Update] Auto-detect mode (-1)
                    if target_class_id == -1:
                         real_cls_id = int(cls_id)
                         if real_cls_id in PET_BEHAVIORS:
                             pet_config = PET_BEHAVIORS[real_cls_id]
                             mode_config = pet_config.get(mode, DEFAULT_BEHAVIOR["playing"])
                             target_props = mode_config["targets"]
        
        # Human Check (0) - Treat as Prop for interaction
        elif cls_id == 0:
            prop_boxes[0] = obj
            
        # Other Props
        else:
            if cls_id in target_props:
                # Keep best confidence
                if cls_id not in prop_boxes or conf > float(prop_boxes[cls_id][4]):
                    prop_boxes[cls_id] = obj

    # ---------------------------------------------------------
    # [Anti-Flickering] Persistence Logic (Logic Sync with Server)
    # ---------------------------------------------------------
    if found_pet:
        if vision_state:
            vision_state["last_pet_box"] = pet_info.copy()
            vision_state["missing_count"] = 0
            vision_state["is_tracking"] = True
    elif vision_state and vision_state.get("is_tracking", False):
        MAX_MISSING = 5
        if vision_state["missing_count"] < MAX_MISSING:
            last_info = vision_state.get("last_pet_box")
            if last_info:
                pet_info = last_info
                found_pet = True
                
                # Recover Target Props if in Auto Mode
                if target_class_id == -1 and len(pet_info["box"]) > 5:
                    recovered_cls = int(pet_info["box"][5])
                    if recovered_cls in PET_BEHAVIORS:
                         pet_config = PET_BEHAVIORS[recovered_cls]
                         mode_config = pet_config.get(mode, DEFAULT_BEHAVIOR["playing"])
                         target_props = mode_config["targets"]
                
                vision_state["missing_count"] += 1
        else:
            vision_state["is_tracking"] = False
            vision_state["last_pet_box"] = None

    # 2. Logic Decision (Copy of original Logic)
    
    # [Fix] Update base_response["bbox"] with the Smoothed/Tracked Pet Box
    # This ensures the UI draws the stable box used by logic, not just the raw input.
    # Also visualizes 'Ghost' tracking.
    if found_pet and pet_info["box"]:
        # Reconstruct the bbox list. 
        # We keep props (non-pets) and replace the pet box with the smoothed version.
        new_bbox_list = []
        for box in base_response.get("bbox", []):
            if len(box) > 5:
                cls = int(box[5])
                if cls not in [14, 15, 16]: # Keep non-pets
                    new_bbox_list.append(box)
        
        # Add the Smoothed Pet Box
        new_bbox_list.append(pet_info["box"])
        base_response["bbox"] = new_bbox_list

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
    min_dist_sq = 9999.0
    
    src_points = []
    # If Keypoints available (passed from server inference), use them
    if pet_info.get("nose"): src_points.append(pet_info["nose"])
    if mode == "playing" and pet_info.get("paws"): src_points.extend(pet_info["paws"])
    
    # Fallback to BBox Center if no keypoints (Edge AI usually)
    if not src_points and pet_info["box"]:
        bx = pet_info["box"]
        src_points.append([(bx[0]+bx[2])/2, (bx[1]+bx[3])/2])

    for pid in target_props:
        if pid in prop_boxes:
            target_box = prop_boxes[pid]
            target_cx = (target_box[0] + target_box[2]) / 2
            target_cy = (target_box[1] + target_box[3]) / 2
            
            for sp in src_points:
                dist_sq = calculate_squared_distance(sp, [target_cx, target_cy], x_scale, y_scale)
                if dist_sq < min_dist_sq: min_dist_sq = dist_sq

    # 거리 임계값 (설정값)
    MIN_DIST_SETTINGS = DETECTION_SETTINGS["min_distance"].get(mode, {"easy": 0.25, "hard": 0.15})
    MIN_DISTANCE = MIN_DIST_SETTINGS.get(difficulty, MIN_DIST_SETTINGS["easy"])
    
    is_interacting = (min_dist_sq < MIN_DISTANCE ** 2)
    
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
        # 실패
        fail_msgs = {
            "feeding": "그릇 가까이 가야 해요!",
            "playing": "장난감과 너무 멀어요",
            "interaction": "주인님과 더 가까이!"
        }
        msg = fail_msgs.get(mode, "더 적극적으로 움직여보세요!")
        base_response.update({
            "success": False,
            "message": msg,
            "feedback_message": "distance_fail", 
            "is_specific_feedback": True
        })

    # [Optimization] 결과 캐싱
    if vision_state is not None:
        vision_state["last_response"] = base_response

    return base_response
