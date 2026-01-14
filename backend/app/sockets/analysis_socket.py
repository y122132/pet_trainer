# backend/app/sockets/analysis_socket.py
import json
import time
import asyncio
from fastapi import Depends
from app.db.database import get_db
from app.services import char_service
from app.ai_core.vision import detector
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import AsyncSessionLocal
from app.db.database_redis import RedisManager
from app.core.pet_constants import PET_CLASS_MAP
from fastapi.concurrency import run_in_threadpool
from app.core.security import verify_websocket_token
from app.ai_core.brain.graphs import get_character_response
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter()

        
@router.websocket("/ws/analysis/{user_id}")
async def analysis_endpoint(
    websocket: WebSocket, 
    user_id: int, 
    mode: str = "playing", 
    pet_type: str = "none", 
    difficulty: str = "easy", 
    token: str | None = None,
    db: AsyncSession = Depends(get_db)
    ):
    """
    실시간 분석을 위한 웹소켓 엔드포인트입니다.
    클라이언트(Flutter)로부터 실시간 카메라 프레임을 받아 AI로 분석하고 결과를 반환합니다.

    Args:
        websocket: 웹소켓 연결 객체
        user_id: 사용자 ID (DB 조회 및 기록용)
        mode: 훈련 모드 ('playing'=놀이, 'feeding'=식사, 'interaction'=교감)
        pet_type: 반려동물 종류 ('dog', 'cat') - YOLO 클래스 ID 매핑에 사용
        difficulty: 난이도 ('easy', 'hard') - 판정 기준 완화/강화
        token: 보안 검증용 토큰 (Optional)
    """
    try:
        # [Security] 연결 수락 전 토큰 검증
        await verify_websocket_token(websocket, token)
        await websocket.accept()

        from app.services import user_service
        user = await user_service.get_user(db, user_id)
        nickname = user.nickname if user else f"User_{user_id}"

        print(f"[FSM_WS] 연결 수락: User {user_id}, 모드 {mode}, 펫 {pet_type}, 난이도 {difficulty}", flush=True)

    except Exception as e:
        print(f"[FSM_WS] 연결 실패: {e}")
        return

    # [TEST] Force Auto-Detection (Detect Dog/Cat/Bird dynamically)
    # Original: target_class_id = PET_CLASS_MAP.get(pet_type.lower(), 16)
    target_class_id = -1
    
    # --- FSM 상태 변수 ---
    state = "READY"              # 현재 상태: READY, DETECTING, STAY, SUCCESS
    state_start_time = None      # STAY 상태 시작 시간
    last_detected_time = None    # 마지막으로 '성공'을 감지한 시간
    
    # --- LLM 연동 변수 [NEW] ---
    last_llm_time = 0            # 마지막 메시지 전송 시각
    last_interaction_time = time.time() # 마지막 FSM 상태 변화 시각 (Idle 체크용)
    llm_task = None              # 비동기 LLM 태스크 (Fire-and-forget)

    # --- 헬퍼 함수: LLM 트리거 ---
    async def trigger_llm(action_type, is_success=False, reward=None, feedback="", milestone=False):
        nonlocal last_llm_time
        current_now = time.time()
        
        # 쿨타임 체크 (성공이 아닌 경우 10초, 성공은 즉시)
        cooldown = 10 if not is_success else 0
        if current_now - last_llm_time < cooldown:
            return

        last_llm_time = current_now
        
        # 비동기 실행을 위해 별도 함수로 래핑
        async def run_llm():
            try:
                # DB에서 최신 스탯 조회 (읽기 전용 세션)
                async with AsyncSessionLocal() as db:
                    char_stats = {"strength": 0, "happiness": 0} # Default
                    
                     # [Fix] user_id로 캐릭터 조회 후 char_id 사용
                    # get_character는 char_id를 받도록 설계되어 있음. 
                    
                    # 따라서 먼저 user_id에 해당하는 캐릭터를 찾아야 함.
                    from sqlalchemy import select
                    from app.db.models.character import Character
                    
                    stmt = select(Character).where(Character.user_id == user_id)
                    result = await db.execute(stmt)
                    character_obj = result.scalar_one_or_none()
                    
                    if character_obj:
                         # 캐릭터가 있으면 스탯 로딩
                         character = await char_service.get_character(db, character_obj.id)
                         if character and character.stat:
                             char_stats = {
                                "strength": character.stat.strength,
                                "intelligence": character.stat.intelligence,
                                "agility": character.stat.agility,
                                "happiness": character.stat.happiness,
                                "health": character.stat.health
                            }
                        
                    msg = await get_character_response(
                        user_id=user_id, # [New] Context Memory Key
                        action_type=action_type,
                        current_stats=char_stats,
                        mode=mode,
                        is_success=is_success,
                        reward_info=reward or {},
                        feedback_detail=feedback,
                        milestone_reached=milestone
                    )
                    
                    # 소켓 전송 (비동기)
                    # [Safety] 연결 상태 확인
                    from fastapi.websockets import WebSocketState
                    if websocket.client_state == WebSocketState.CONNECTED:
                        await websocket.send_json({
                            "char_message": msg,  # [Change] chat_message -> char_message
                            "message": "AI: " + msg[:15] + "...", # 시스템 로그용 요약
                            "status": "keep" # 상태 유지
                        })
                    else:
                        print(f"[LLM_SKIP] 소켓 연결 끊김 (User {user_id})")
            except Exception as ex:
                print(f"[LLM_ERROR] {ex}")

        # 백그라운드 태스크 생성
        asyncio.create_task(run_llm())

    # [NEW] 연결 직후 초기 인사 (Greeting)
    # 앱 시작 시 침묵(Startup Silence) 방지
    await trigger_llm("greeting", is_success=False)
    
    # [NEW] Anti-Flickering State
    vision_state = {
        "last_pet_box": None,
        "missing_count": 0,
        "is_tracking": False,
        "last_response": None, # [NEW] Zero-Order Hold (프레임 스킵용 캐시)
        "best_frame_data": None, # [NEW] Best Shot (Binary)
        "best_conf": 0.0,        # [NEW] Best Shot Confidence
        "best_bbox": []          # [NEW] Best Shot BBox for cropping (Optional)
    }

    
    # [Optimization] 프레임 스킵 카운터
    frame_count = 0
    PROCESS_INTERVAL = 1  # 3프레임마다 1번 처리 # [Tuning] 1로 변경하여 반응성 최우선

    try:
        while True:
            # 타임아웃을 두어 receive_bytes가 무한정 막히지 않게 할 수도 있지만,
            # Idle 처리를 위해 asyncio.wait_for를 쓸 수도 있음.
            # [Fix] 타임아웃 방식이 아닌, 프레임 수신 여부와 관계없이 시간 체크
            try:
                # [Modified] Support both Bytes (Image) and Text (JSON Result)
                # `receive()` returns a dict: {'type': 'websocket.receive', 'bytes': ..., 'text': ...}
                message = await websocket.receive()
                
                if 'bytes' in message and message['bytes']:
                    image_bytes = message['bytes']
                    # [Server-side Logic]
                    
                elif 'text' in message and message['text']:
                    # [Edge AI Logic]
                    # Client sent pre-processed result (JSON)
                    import json
                    edge_result = json.loads(message['text'])
                    
                    # [Fix] Construct base_response with dimensions for Logic Aspect Ratio safety
                    # Default to 640 if missing (but Frontend sends it now)
                    base_resp_input = {
                        "width": edge_result.get("width", 640),
                        "height": edge_result.get("height", 640),
                        "bbox": edge_result.get('bbox', []),
                        "pet_keypoints": edge_result.get('pet_keypoints', []),
                        "human_keypoints": edge_result.get('human_keypoints', [])
                    }

                    # [Fix] Invoke Logic Layer (Server-side Logic Reuse)
                    result = await run_in_threadpool(
                        detector.process_logic_only,
                        detected_objects=edge_result.get('bbox', []),
                        mode=mode,
                        target_class_id=target_class_id,
                        difficulty=difficulty,
                        vision_state=vision_state,
                        base_response=base_resp_input # [NEW] Pass dimensions
                    )
                    
                    # Ensure minimal keys exist (Should be handled by process_logic_only, but safe check)
                    if "success" not in result: result["success"] = False
                    
                    # [Fix] Propagate Frame ID for Latency Calculation
                    # Frontend expects 'frame_id' to match the request to calculate latency
                    if 'frame_id' in edge_result:
                        result['frame_id'] = edge_result['frame_id']
                    
                    
                    # [Fix] Trust Client's Success Decision (Edge AI Timer Completion)
                    
                    # [Fix] Trust Client's Success Decision (Edge AI Timer Completion)
                    # BUT respect server-side COOLDOWN to prevent spam/looping
                    if edge_result.get('status') == 'success' and state != "COOLDOWN":
                        state = "SUCCESS"
                        result["success"] = True # Align vision success with FSM state
                        
                        # [Fix] Force Generate Reward if Server Logic didn't trigger 'is_interacting'
                        if not result.get("base_reward"):
                            import numpy as np
                            # Fallback Reward Generation (Same logic as detector.py)
                            if mode == "playing":
                                action_type = "playing_fetch"
                                result["base_reward"] = {"stat_type": "strength", "value": 3} if np.random.rand() < 0.7 else {"stat_type": "agility", "value": 3}
                                result["bonus_points"] = 2
                            elif mode == "feeding":
                                action_type = "feeding"
                                result["base_reward"] = {"stat_type": "health", "value": 3} if np.random.rand() < 0.7 else {"stat_type": "defense", "value": 3}
                                result["bonus_points"] = 1
                            elif mode == "interaction":
                                action_type = "interaction_owner"
                                result["base_reward"] = {"stat_type": "happiness", "value": 4} if np.random.rand() < 0.7 else {"stat_type": "intelligence", "value": 3}
                                result["bonus_points"] = 3
                            
                            result["action_type"] = action_type
                    
                    # Pass through to FSM Logic below (Skip 'run_in_threadpool(detector...)')
                    image_bytes = None # Skip decoding
                    
                else:
                    # Ping/Pong or Empty
                    continue
                    
            except Exception:
                break
            
            image_bytes = None
            
            # A. Control Message Handling
            if "text" in message:
                is_control = False
                try:
                    data = json.loads(message["text"])
                    if data.get("type") == "change_mode":
                        new_mode = data.get("mode")
                        if new_mode in ["playing", "feeding", "interaction"]:
                            mode = new_mode
                            # Reset State
                            state = "READY"
                            state_start_time = None
                            last_detected_time = None
                            vision_state["is_tracking"] = False # Vision state reset
                            vision_state["best_frame_data"] = None # Reset Best Shot
                            vision_state["best_conf"] = 0.0
                            
                            print(f"[FSM_WS] User {user_id} switched to mode: {mode}")
                            
                            await websocket.send_json({
                                "status": "info",
                                "message": f"모드가 '{mode}'로 변경되었습니다."
                            })
                            is_control = True
                            
                    elif data.get("type") == "ping":
                        # Keep-alive
                        is_control = True
                        pass
                except:
                    pass
                
                if is_control:
                    continue # Skip vision processing for control messages

            # B. Image Data Handling
            if "bytes" in message:
                image_bytes = message["bytes"]

            frame_count += 1

            # 1. Idle 체크 (매 프레임마다 시간 비교)
            # 마지막 상호작용(성공, 실패, 감지 등)으로부터 20초 경과 시
            if time.time() - last_interaction_time > 20.0:
                 # 20초 이상 잠수 -> 심심함 표현# trigger_llm이 성공했을 때만 리셋 등 전략 필요.
                 # 여기서는 trigger_llm 호출 후 시간을 리셋하여 20초 뒤에 다시 칭얼대도록 함
                 # 비동기 호출 (결과 기다리지 않음)
                 await trigger_llm("idle", is_success=False)
                 
                 # 메시지를 보냈으므로 다시 20초 카운트 (재촉 주기)
                 last_interaction_time = time.time()
            
            current_time = time.time()
            
            # [Branching] Server-side Inference vs Edge Result
            if image_bytes is not None:
                # [Server-side Inference]
                
                # [NEW] Frame ID Extraction (Last 4 bytes)
                frame_id = -1
                if len(image_bytes) > 4:
                    # Big Endian Integer parsing
                    frame_id = int.from_bytes(image_bytes[-4:], byteorder='big')
                    # Remove ID from image data
                    image_bytes = image_bytes[:-4]

                # 비전 처리 (CPU/GPU)
                result = await run_in_threadpool(
                    detector.process_frame, 
                    image_bytes, 
                    mode, 
                    target_class_id, 
                    difficulty,
                    frame_index=frame_count,
                    process_interval=PROCESS_INTERVAL,
                    frame_id=frame_id,  # [NEW] Pass ID
                    vision_state=vision_state # [NEW] Inject State
                )
            
            # [Common] Post-Inference FSM Logic



            if result.get("skipped", False):
                continue
            is_success_vision = result.get("success", False)

            # --- COOLDOWN Logic ---
            if state == "COOLDOWN":
                elapsed = current_time - state_start_time
                if elapsed >= 3.0:
                    state = "READY"
                    state_start_time = None
                    # Transition to READY allows immediate re-detection in next lines
                    # Optional: Send "Ready" message
                else:
                    # Still in cooldown - block other states
                    response = result.copy()
                    response.update({
                        "status": "stay", 
                        "message": f"잠시 휴식... {3.0 - elapsed:.1f}초",
                        "is_specific_feedback": True
                    })
                    await websocket.send_json(response)
                    continue

            # --- FSM 로직 ---
            response = result.copy()

            if is_success_vision:
                last_interaction_time = current_time # 상호작용 발생
                last_detected_time = current_time
                
                if state == "READY":
                    state = "DETECTING"
                    response.update({"status": "detecting", "message": "동작 감지 시작!"})
                    await websocket.send_json(response)
                
                elif state == "DETECTING":
                    state = "STAY"
                    state_start_time = current_time
                    response.update({"status": "stay", "message": "좋아요, 자세를 3초간 유지하세요!"})
                    await websocket.send_json(response)
                
                elif state == "STAY":
                    hold_duration = current_time - state_start_time
                    if hold_duration >= 3:
                        state = "SUCCESS"
                    else:
                        response.update({"status": "stay", "message": f"자세 유지... {3 - hold_duration:.1f}초"})
                        
                        # [NEW] Best Shot Selection
                        # 현재 프레임의 자신감(Conf)이 기존 최고치보다 높으면 갱신
                        current_conf = result.get("conf_score", 0.0)
                        if image_bytes and current_conf > vision_state["best_conf"]:
                            vision_state["best_conf"] = current_conf
                            vision_state["best_frame_data"] = image_bytes # Keep binary
                            vision_state["best_bbox"] = result.get("bbox", [])
                            # print(f"[BestShot] Updated: {current_conf:.4f}", flush=True)

                        await websocket.send_json(response)
            
            else: # is_success_vision is False
                if state == "STAY":
                    # 유예 시간 (Grace Period) 체크
                    # [UX Improvement] 1.5초 -> 0.8초 단축 (반응성 향상)
                    if current_time - last_detected_time > 0.8:
                        # [실패 전환]
                        state = "READY"
                        state_start_time = None
                        vision_state["best_frame_data"] = None # Reset on Fail
                        vision_state["best_conf"] = 0.0
                        response.update({"status": "fail", "message": "동작이 끊겼습니다."})
                        await websocket.send_json(response)
                        
                        last_interaction_time = current_time # 상호작용(실패) 발생
                        
                        # [NEW] 실패 시 격려 메시지
                        await trigger_llm(mode, is_success=False, feedback="pose_unstable")
                        
                    else:
                        # [Fixed] Grace Period 처리
                        hold_duration = current_time - state_start_time
                        response.update({
                            "status": "stay", 
                            "message": f"자세 유지... {3 - hold_duration:.1f}초 (인식 불안정)"
                        })
                        await websocket.send_json(response)
                        
                elif state == "DETECTING":
                    state = "READY"
                    # 단순 감지 실패는 메시지 생성 안 함 (너무 빈번함)
                
                # READY 상태 반복 전송 방지 (클라이언트 부하 감소)
                if state == "READY":
                    # [Fix] 단순 "찾는 중" 메시지는 보내지 않음 (캐릭터 대화 방해 방지)
                    if not result.get("is_specific_feedback", False):
                        response.pop("message", None)
                    
                    response.update({"status": "fail"})
                    await websocket.send_json(response)

            # --- 성공 상태 처리 ---
            if state == "SUCCESS":
                print(f"[FSM_SUCCESS] User {user_id} 훈련 성공!")
                last_interaction_time = current_time
                
                # DB 업데이트
                response_data = {}
                try:
                    async with AsyncSessionLocal() as db:
                        # [Fix] user_id로 character_id 조회
                        from sqlalchemy import select
                        from app.db.models.character import Character
                        stmt = select(Character).where(Character.user_id == user_id)
                        char_res = await db.execute(stmt)
                        character_obj = char_res.scalar_one_or_none()
                        
                        if not character_obj:
                            raise Exception("Character not found for user")
                            
                        # char_id를 사용하여 스탯 업데이트 호출
                        service_result = await char_service.update_stats_from_yolo_result(db, character_obj.id, result)
                        
                        if service_result:
                            # [NEW] 1. Best Shot Saving (Execute BEFORE LLM)
                            best_shot_url = None
                            if vision_state["best_frame_data"]:
                                try:
                                    import os
                                    from datetime import datetime
                                    
                                    # Save Image to Local Disk
                                    today_str = datetime.now().strftime("%Y%m%d")
                                    upload_dir = f"uploads/{today_str}"
                                    os.makedirs(upload_dir, exist_ok=True)
                                    
                                    filename = f"best_shot_{user_id}_{int(time.time())}.jpg"
                                    filepath = f"{upload_dir}/{filename}"
                                    
                                    with open(filepath, "wb") as f:
                                        f.write(vision_state["best_frame_data"])
                                        
                                    # Generate URL (Relative path for Frontend)
                                    best_shot_url = f"/uploads/{today_str}/{filename}"
                                    print(f"[BestShot] Saved: {filepath}")

                                except Exception as e:
                                    print(f"[BestShot] Save Error: {e}")
                                    import traceback
                                    traceback.print_exc()

                            # LLM 호출을 위한 정보 준비
                            updated_stat = service_result["stat"]
                            
                            # [Changed] Pass best_shot_url to LLM
                            msg = await get_character_response(
                                user_id=user_id, 
                                action_type=result.get("action_type", "action").replace("_", " ").title(),
                                current_stats={
                                    "strength": updated_stat.strength,
                                    "health": updated_stat.health,
                                    "happiness": updated_stat.happiness
                                },
                                mode=mode,
                                is_success=True,
                                reward_info=result.get("base_reward", {}),
                                feedback_detail=result.get("feedback_message", ""),
                                daily_count=service_result.get("daily_count", 0),
                                milestone_reached=service_result.get("milestone_reached"),
                                best_shot_url=best_shot_url # [New] Pass Best Shot URL
                            )
                            
                            response_data = {
                                "status": "success",
                                "char_message": msg, 
                                "message": "훈련 성공!", 
                                "base_reward": result.get("base_reward", {}),
                                "bonus_points": result.get("bonus_points", 0),
                                "count": service_result.get("daily_count", 0),
                                "bbox": [],
                                "level_up_info": service_result.get("level_up_info", {}), 
                                "pet_keypoints": [],
                                "human_keypoints": [],
                                "best_shot_url": best_shot_url # [New] Send URL to Client
                            }
                            
                            # [NEW] 2. Create Diary Entry (After LLM)
                            if best_shot_url:
                                try:
                                    from app.db.models.diary import Diary
                                    from datetime import datetime
                                    
                                    diary_entry = Diary(
                                        user_id=user_id,
                                        image_url=best_shot_url, 
                                        content=msg, # Character's comment (Image-Aware)
                                        tag="훈련인증",
                                        created_at=datetime.utcnow()
                                    )
                                    db.add(diary_entry)
                                    await db.commit() 
                                    print(f"[BestShot] Diary Uploaded with msg: {msg[:20]}...")
                                    
                                except Exception as e:
                                    print(f"[BestShot] Diary Error: {e}")
                            
                            # Reset Best Shot State for next round
                            vision_state["best_frame_data"] = None
                            vision_state["best_conf"] = 0.0
                        else:
                             raise Exception("DB Error")
                             
                except Exception as e:
                    print(f"Error: {e}")
                    import traceback
                    traceback.print_exc()
                    response_data = {
                        "status": "success",
                        "message": "훈련 성공! (보상 오류)",
                        "base_reward": result.get("base_reward", {}),
                        "bonus_points": 0,
                        "bbox": []
                    }
                
                await websocket.send_json(response_data)
                
                # [UX Improvement] Switch to COOLDOWN instead of READY
                state = "COOLDOWN"
                state_start_time = current_time # Reset for cooldown timer
                last_detected_time = None

    except WebSocketDisconnect:
        print(f"[FSM_WS] 사용자 {nickname} 연결 종료", flush=True)
    except Exception as e:
        print(f"[FSM_WS] 소켓 에러 발생: {e}", flush=True)
    finally:
        try:
            await websocket.close()
        except:
            pass