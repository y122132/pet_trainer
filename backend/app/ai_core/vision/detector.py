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
    file_size_kb = len(image_bytes) / 1024
    print(f"[Detector] Input Image Size: {width}x{height} (Ratio: {width/height:.2f}), File Size: {file_size_kb:.1f}KB", flush=True)

    # ---------------------------------------------------------
    # 2. 반려동물 & 사물 탐지 (YOLO Object Detection)
    # ---------------------------------------------------------
    
    # [Logic Separation] 추론용 임계값 vs 로직용 임계값 분리
    # 추론: 0.25 (YOLO 기본 권장값, 노이즈 필터링)
    # 로직: 0.4 (확실한 인식만 허용하여 게임 품질 확보)
    INFERENCE_CONF = 0.25
    LOGIC_CONF = 0.6 if difficulty == "hard" else 0.4
    
    # [Critical Fix] BGR -> RGB 변환
    # OpenCV는 BGR을 사용하지만, YOLO 모델(Ultralytics)은 RGB를 기대함.
    # 색상이 반전되면(예: 갈색 강아지 -> 파란색) 모델이 오인식(사람 등)할 수 있음.
    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    
    # YOLO 추론 수행 (imgsz=640 명시하여 비율 유지 리사이징/패딩 보장)
    results_detect = model_detect(frame_rgb, conf=INFERENCE_CONF, imgsz=640, verbose=False)
    
    found_pet = False
    pet_box = [] # [x1, y1, x2, y2] (정규화된 좌표)
    best_conf = 0.0
    
    # [Config Load] 현재 모드에 필요한 타겟 물건 설정 미리 가져오기
    pet_config = PET_BEHAVIORS.get(target_class_id, DEFAULT_BEHAVIOR)
    mode_config = pet_config.get(mode, pet_config["playing"]) 
    target_props = mode_config["targets"]

    detected_objects = [] # 프론트엔드 시각화용 (모든 관련 객체)
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

            # [Visual] 시각화 리스트에 추가 (LOGIC_CONF 이상, 그리고 펫이나 타겟 물건인 경우)
            # 사용자가 "이상한 것까지 잡히지 않게"라고 했으므로 필터링 적용
            if conf >= LOGIC_CONF:
                 if cls_id == target_class_id or cls_id in target_props:
                      # [x1, y1, x2, y2, conf, cls]
                      detected_objects.append([nx1, ny1, nx2, ny2, float(conf), float(cls_id)])

            # A. 반려동물 찾기 (설정된 target_class_id와 일치하는지 확인)
            # [Fix] 시각적 박스와 로직의 일관성을 위해 LOGIC_CONF 이상일 때만 로직 인정
            if cls_id == target_class_id and conf >= LOGIC_CONF:
                if conf > best_conf: # 가장 신뢰도 높은 객체 선택
                    best_conf = conf
                    found_pet = True
                    # [nx1, ny1, nx2, ny2, conf, cls] 형태로 확장
                    pet_box = [nx1, ny1, nx2, ny2, float(conf), float(cls_id)]
            
            # B. 타겟 물건(장난감, 그릇 등) 찾기
            # [Fix] 시각적 박스와 로직의 일관성을 위해 LOGIC_CONF 이상일 때만 로직 인정
            if cls_id in target_props and conf >= LOGIC_CONF:
                # 해당 클래스의 객체가 여러 개일 경우, 일단 가장 높은 신뢰도 or 마지막 발견된 것 저장
                # (상호작용 로직에서는 prop_boxes에 있는 것을 사용)
                # 더 정교하게 하려면 리스트로 관리해야 하지만, 현재 로직(단순 거리 비교) 유지
                # prop_boxes는 [x1, y1, x2, y2] 만 저장하는 구조였음.
                if cls_id not in prop_boxes or conf > (prop_boxes.get(cls_id, [])[4] if len(prop_boxes.get(cls_id, [])) > 4 else -1):
                     prop_boxes[cls_id] = current_box + [conf] # Store conf temporarily for comparison
                     if cls_id not in props_detected: # Ensure unique class IDs
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
    
    # [Logic Fix] best_conf(타겟)가 max_conf_any(전체)보다 높으면 갱신 (논리적 정합성)
    if best_conf > max_conf_any:
        max_conf_any = best_conf
        max_conf_cls = target_class_id
    
    # [Debug] 전체 탐지 로그 출력 (필수)
    print(f"[Detector] All detections: {all_detections_summary}", flush=True)

    # [NEW] 교감 모드 상세 피드백 (반려동물 미감지 시)
    if not found_pet and mode == "interaction":
        # 사람이 있는지 확인 (class ID 0은 'person')
        person_detected = any(obj[5] == 0 for obj in detected_objects) # detected_objects는 [nx1, ny1, nx2, ny2, conf, cls]
        if person_detected:
            # 사람은 있는데 펫이 없음
            return {
                "success": False,
                "message": "주인님은 보이는데, 강아지는 어디 있나요?", # 구체적 피드백
                "feedback_message": "owner_found_no_pet",
                "keypoints": [],
                "width": width,
                "height": height,
                "conf_score": best_conf,
                "debug_max_conf": max_conf_any,
                "debug_max_cls": max_conf_cls,
                "bbox": detected_objects # 사람 박스는 포함됨
            }

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
            "debug_max_cls": max_conf_cls,   # 타겟 무관 최고 클래스
            "bbox": detected_objects # [Change] pet_box 대신 전체 감지 객체 리스트 반환 (프론트 변경 필요)
        }

    # [Moved Up] 현재 모드에 필요한 타겟 물건 설정은 위에서 이미 가져옴
    
    # 화면에 타겟 물건이 하나라도 있는지 확인
    
    # 화면에 타겟 물건이 하나라도 있는지 확인
    has_target = any(p in props_detected for p in target_props)
    
    # [NEW] 상세 피드백: 반려동물은 찾았는데 도구(그릇/장난감)가 없는 경우
    # has_target이 False이고 found_pet이 True일 때 실행
    missing_prop_msg = ""
    if found_pet and not has_target:
        if mode == "feeding":
            missing_prop_msg = "강아지는 보이는데, 밥그릇은 어디 있나요?"
        elif mode == "playing":
            missing_prop_msg = "강아지는 보이는데, 장난감(공)은 어디 있나요?"
        elif mode == "interaction":
            missing_prop_msg = "강아지는 보이는데, 주인님은 어디 계세요?"

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
            if min_distance < 0.3:
                is_interacting = True
            else:
                distance_msg = "주인님과 더 가까이!"
    
    # [NEW] 교감 모드 피드백 강화
    # 타겟(주인)은 감지되었는데 반려동물이 없는 경우
    elif mode == "interaction" and not has_target:
        # interaction 모드의 target_props는 "person"임. 
        # has_target이 False라면 사람이 없다는 뜻이므로 "주인님 어디 계세요?"가 맞고,
        # has_target(사람)은 True인데 여기까지 왔다면(is_interacting 변수 범위 밖),
        # 애초에 pet_box가 없는 경우(Detector 초입)를 처리해야 함.
        
        # 현재 코드 구조상 process_frame 초반에 detections를 확인해야 함.
        # 여기는 has_target(사람있음) 일때만 진입하므로,
        # 사람이 없어서 여기를 못 들어오는 경우 -> "주인을 찾는 중" (기본 메시지)
        # 사람이 있는데 반려동물이 감지 안 된 경우 -> detector.py 상단에서 처리 필요.
        pass
    
    # [Logic Refine] has_target 변수 자체가 "target_props(사람)가 있냐"임.
    # 하지만 이 블록은 "반려동물(pet_box)"도 감지되었을 때만 실행됨 (detector.py 상단 로직 참조)
    # 따라서, 반려동물이 없으면 이 블록 자체를 건너뜀.
    
    # 난이도 'hard'일 경우 기준 강화 (더 엄격한 판정)
    
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

    # [NEW] 도구 미감지 시 메시지 덮어쓰기
    is_specific_feedback = False

    if missing_prop_msg:
        message = missing_prop_msg
        feedback_message = "prop_missing"
        is_specific_feedback = True
    # 거리 부족 시 메시지 덮어쓰기 (도구는 있는데 상호작용 실패)
    elif distance_msg:
        message = distance_msg
        feedback_message = "distance_fail"
        is_specific_feedback = True

    # 시각화용 데이터 (스켈레톤 등)
    normalized_keypoints = []

    if has_target:
        if is_interacting:
            # [성공 판정]
            message = mode_config["success_msg"]
            feedback_message = mode_config["feedback_success"]
            is_specific_feedback = True
            
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
            is_specific_feedback = True # 상호작용 시도 중인 피드백이므로 중요함
            
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
        "bbox": detected_objects, # [Change] 전체 객체 리스트
        "width": width,
        "height": height,
        "conf_score": best_conf,
        "base_reward": base_reward,
        "bonus_points": bonus_points,
        "is_specific_feedback": is_specific_feedback
    }
