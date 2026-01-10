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

    # 대소문자 무시 및 기본값 설정 (기본값: 16 - 강아지)
    target_class_id = PET_CLASS_MAP.get(pet_type.lower(), 16)
    
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
        "last_response": None # [NEW] Zero-Order Hold (프레임 스킵용 캐시)
    }

    
    # [Optimization] 프레임 스킵 카운터
    frame_count = 0
    PROCESS_INTERVAL = 1  # 3프레임마다 1번 처리

    try:
        while True:
            # 타임아웃을 두어 receive_bytes가 무한정 막히지 않게 할 수도 있지만,
            # Idle 처리를 위해 asyncio.wait_for를 쓸 수도 있음.
            # [Fix] 타임아웃 방식이 아닌, 프레임 수신 여부와 관계없이 시간 체크
            try:
                image_bytes = await websocket.receive_bytes()
            except Exception:
                break
            
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

            if result.get("skipped", False):
                continue
            is_success_vision = result.get("success", False)

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
                        await websocket.send_json(response)
            
            else: # is_success_vision is False
                if state == "STAY":
                    # 유예 시간 (Grace Period) 체크
                    # [Fix] 0.5초 -> 1.5초 늘려주어 잠깐의 인식 실패나 흔들림에 관대해짐
                    if current_time - last_detected_time > 1.5:
                        # [실패 전환]
                        state = "READY"
                        state_start_time = None
                        response.update({"status": "fail", "message": "동작이 끊겼습니다."})
                        await websocket.send_json(response)
                        
                        last_interaction_time = current_time # 상호작용(실패) 발생
                        
                        # [NEW] 실패 시 격려 메시지 (Semantic Compression: 단순 실패가 아니라 '자세 무너짐'으로 전달)
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
                    # response는 result.copy()이므로 이미 'message'가 들어있음.
                    # 따라서 중요하지 않으면 'message' 키를 제거해야 함.
                    
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
                            # LLM 호출을 위한 정보 준비 (여기서는 직접 호출하지 않고 trigger 함수 사용 권장하지만,
                            # service_result가 필요하므로 인라인 혹은 trigger 함수 확장 필요)
                            
                            # 기존 구조 유지하되 LLM 부분만 교체
                            updated_stat = service_result["stat"]
                            
                            msg = await get_character_response(
                                user_id=user_id, # [New] Context Memory Key
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
                                milestone_reached=service_result.get("milestone_reached")
                            )
                            
                            response_data = {
                                "status": "success",
                                "char_message": msg, # [Change] char_message
                                "message": "훈련 성공!", # 시스템 메시지 고정
                                "base_reward": result.get("base_reward", {}),
                                "bonus_points": result.get("bonus_points", 0),
                                "count": service_result.get("daily_count", 0),
                                "bbox": []
                            }
                        else:
                             raise Exception("DB Error")
                             
                except Exception as e:
                    print(f"Error: {e}")
                    response_data = {
                        "status": "success",
                        "message": "훈련 성공! (보상 오류)",
                        "base_reward": result.get("base_reward", {}),
                        "bonus_points": 0,
                        "bbox": []
                    }
                
                await websocket.send_json(response_data)
                
                state = "READY"
                state_start_time = None
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