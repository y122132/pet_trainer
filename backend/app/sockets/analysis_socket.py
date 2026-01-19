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

# [Refactored Imports]
from app.game.training_session import TrainingSessionManager
from app.services.training_service import TrainingResultService

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
    실시간 분석을 위한 웹소켓 엔드포인트 (Refactored)
    """
    try:
        await verify_websocket_token(websocket, token)
        await websocket.accept()

        from app.services import user_service
        user = await user_service.get_user(db, user_id)
        nickname = user.nickname if user else f"User_{user_id}"
        print(f"[FSM_WS] 연결 수락: User {user_id}, 모드 {mode}", flush=True)

    except Exception as e:
        print(f"[FSM_WS] 연결 실패: {e}")
        return

    # --- Services Initialization ---
    session_manager = TrainingSessionManager()
    result_service = TrainingResultService()
    
    target_class_id = -1
    PROCESS_INTERVAL = 1
    frame_count = 0

    # Initial Greeting
    await result_service.trigger_llm_event(websocket, user_id, mode, "greeting", is_success=False)
    
    try:
        while True:
            # 1. Idle Check
            if time.time() - session_manager.last_interaction_time > 20.0:
                await result_service.trigger_llm_event(websocket, user_id, mode, "idle", is_success=False)
                session_manager.last_interaction_time = time.time()

            # 2. Receive Data
            try:
                message = await websocket.receive()
            except Exception:
                break # Connection closed
            
            # 3. Control Message Handling
            if "text" in message:
                try:
                    data = json.loads(message["text"])
                    if data.get("type") == "change_mode":
                        new_mode = data.get("mode")
                        if new_mode in ["playing", "feeding", "interaction"]:
                            mode = new_mode
                            session_manager.reset()
                            print(f"[FSM_WS] User {user_id} switched to mode: {mode}")
                            await websocket.send_json({"status": "info", "message": f"모드가 '{mode}'로 변경되었습니다."})
                            continue
                    elif data.get("type") == "ping":
                        continue
                except:
                    pass
            
            # 4. Vision Processing
            image_bytes = None
            result = {}
            
            # A. Image Bytes (Server-side Inference)
            if 'bytes' in message and message['bytes']:
                image_bytes = message['bytes']
                frame_id = -1
                if len(image_bytes) > 4:
                    frame_id = int.from_bytes(image_bytes[-4:], byteorder='big')
                    image_bytes = image_bytes[:-4]
                
                result = await run_in_threadpool(
                    detector.process_frame, 
                    image_bytes, 
                    mode, 
                    target_class_id, 
                    difficulty,
                    frame_index=frame_count,
                    process_interval=PROCESS_INTERVAL,
                    frame_id=frame_id,
                    vision_state=session_manager.vision_state
                )

            # B. Text JSON (Edge AI Result)
            elif 'text' in message and message['text']:
                try:
                    edge_result = json.loads(message['text'])
                    # Edge 모드일 때 process_logic_only 호출 등 기존 로직 유지
                    # 여기서는 간단히 detector.process_logic_only 호출
                    base_resp_input = {
                         "width": edge_result.get("width", 640),
                         "height": edge_result.get("height", 640),
                         "bbox": edge_result.get('bbox', []),
                         "pet_keypoints": edge_result.get('pet_keypoints', []),
                         "human_keypoints": edge_result.get('human_keypoints', [])
                    }
                    result = await run_in_threadpool(
                        detector.process_logic_only,
                        detected_objects=edge_result.get('bbox', []),
                        mode=mode,
                        target_class_id=target_class_id,
                        difficulty=difficulty,
                        vision_state=session_manager.vision_state,
                        base_response=base_resp_input
                    )
                    
                    if "success" not in result: result["success"] = False
                    if 'frame_id' in edge_result: result['frame_id'] = edge_result['frame_id']
                    
                    # Edge Best Shot Handling
                    if 'best_shot_base64' in edge_result:
                         import base64
                         try:
                             img_data = base64.b64decode(edge_result['best_shot_base64'])
                             session_manager.update_best_shot(img_data, edge_result.get('conf_score', 1.0), [])
                         except: pass
                    
                    # Edge Success Signal Trust
                    if edge_result.get('status') == 'success' and session_manager.state not in ["SUCCESS", "COOLDOWN"]:
                        result["success"] = True
                        if not result.get("base_reward"):
                             # Fallback Reward
                             import numpy as np
                             action_type = "playing_fetch" if mode=="playing" else "feeding" if mode=="feeding" else "interaction_owner"
                             result["base_reward"] = {"stat_type": "strength", "value": 3} 
                             result["bonus_points"] = 2
                             result["action_type"] = action_type

                except Exception as e:
                    print(f"[Edge Error] {e}")
                    continue

            if not result: continue
            if result.get("skipped", False): continue
            
            frame_count += 1
            current_time = time.time()
            
            # 5. FSM Transition
            response = session_manager.process_fsm(result, image_bytes, current_time)
            
            # 6. Success Handling (Transitioned to SUCCESS just now or from Edge)
            # process_fsm 내부에서 SUCCESS로 바뀌었거나, Edge가 SUCCESS를 보내서 result['success']가 True인 경우
            # 하지만 process_fsm은 3초 유지가 끝나야 SUCCESS를 반환함.
            
            # Edge Case: Edge AI sent 'success', result['success'] is True. 
            # process_fsm sees result['success'] is True -> updates state logic.
            # If state becomes SUCCESS in session_manager, we act.
            
            if session_manager.state == "SUCCESS" and str(response.get("status")) != "cooldown": 
                # "cooldown" check added just in case logic sets it immediately
                # But actually we should check if we haven't processed it yet.
                # session_manager.state stays SUCCESS until we reset it to COOLDOWN.
                
                print(f"[FSM_SUCCESS] User {user_id} 훈련 성공!")
                
                # Heavy Lifting
                # We need best shot data.
                best_shot = session_manager.vision_state["best_frame_data"]
                # If Edge mode, it was updated via update_best_shot
                
                await result_service.process_training_success(websocket, user_id, mode, result, best_shot)
                
                # Setup Cooldown
                session_manager.start_cooldown(current_time)
                
            elif response.get("need_feedback"):
                # Fails
                fb_type = response.pop("need_feedback")
                await websocket.send_json(response)
                await result_service.trigger_llm_event(websocket, user_id, mode, mode, is_success=False, feedback=fb_type)
                
            else:
                # Normal State Update
                await websocket.send_json(response)

    except WebSocketDisconnect:
        print(f"[FSM_WS] 사용자 {nickname} 연결 종료")
    except Exception as e:
        print(f"[FSM_WS] 소켓 에러 발생: {e}")
        import traceback
        traceback.print_exc()
    finally:
        try: await websocket.close()
        except: pass