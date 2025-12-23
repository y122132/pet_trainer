from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool
from app.ai_core.vision import detector
from app.services import char_service
from app.db.database import AsyncSessionLocal
from app.core.pet_constants import PET_CLASS_MAP
import json
import time

router = APIRouter()

@router.websocket("/ws/analysis/{user_id}")
async def analysis_endpoint(websocket: WebSocket, user_id: int, mode: str = "playing", pet_type: str = "none", difficulty: str = "easy"):
    """
    실시간 분석을 위한 웹소켓 엔드포인트입니다.
    클라이언트(Flutter)로부터 실시간 카메라 프레임을 받아 AI로 분석하고 결과를 반환합니다.

    Args:
        websocket: 웹소켓 연결 객체
        user_id: 사용자 ID (DB 조회 및 기록용)
        mode: 훈련 모드 ('playing'=놀이, 'feeding'=식사, 'interaction'=교감)
        pet_type: 반려동물 종류 ('dog', 'cat') - YOLO 클래스 ID 매핑에 사용
        difficulty: 난이도 ('easy', 'hard') - 판정 기준 완화/강화
    """
    try:
        await websocket.accept()
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
    
    try:
        while True:
            image_bytes = await websocket.receive_bytes()
            current_time = time.time()
            
            result = await run_in_threadpool(detector.process_frame, image_bytes, mode, target_class_id, difficulty)
            is_success = result.get("success", False)

            # --- FSM 로직 시작 ---
            if is_success:
                last_detected_time = current_time
                if state == "READY":
                    state = "DETECTING"
                    await websocket.send_json({"status": "detecting", "message": "동작 감지 시작!"})
                
                elif state == "DETECTING":
                    state = "STAY"
                    state_start_time = current_time
                    await websocket.send_json({"status": "stay", "message": "좋아요, 자세를 3초간 유지하세요!"})
                
                elif state == "STAY":
                    hold_duration = current_time - state_start_time
                    if hold_duration >= 3:
                        state = "SUCCESS"
                    else:
                        await websocket.send_json({"status": "stay", "message": f"자세 유지... {3 - hold_duration:.1f}초"})
            
            else: # is_success가 False일 때
                if state == "STAY":
                    # 유예 시간 (Grace Period) 체크
                    if current_time - last_detected_time > 0.5:
                        state = "READY"
                        state_start_time = None
                        await websocket.send_json({"status": "fail", "message": "동작이 끊겼습니다. 다시 시도하세요."})
                elif state == "DETECTING":
                    # 감지 시작 직후 실패 시 바로 초기화
                    state = "READY"
                
                # READY 상태에서는 실패 메시지를 계속 전송
                if state == "READY":
                    await websocket.send_json({
                        "status": "fail", 
                        "message": result.get("message", "대기 중..."),
                        "feedback": result.get("feedback_message", "")
                    })

            # --- 성공 상태 처리 ---
            if state == "SUCCESS":
                print(f"[FSM_SUCCESS] User {user_id} 훈련 성공! 보상 지급 절차 시작")
                response_data = {}
                try:
                    # DB 업데이트 및 스탯 적용 (1회만 실행)
                    async with AsyncSessionLocal() as db:
                        service_result = await char_service.update_stats_from_yolo_result(db, user_id, result)
                        
                        if service_result:
                            updated_stat = service_result["stat"]
                            
                            # LLM을 통해 동적 응답 생성
                            from app.ai_core.brain.graphs import get_character_response
                            ai_message = await get_character_response(
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
                            
                            # 최종 성공 데이터 구성
                            response_data = {
                                "status": "success",
                                "message": ai_message,
                                "base_reward": result.get("base_reward", {}),
                                "bonus_points": result.get("bonus_points", 0),
                                "count": service_result.get("daily_count", 0)
                            }
                        else:
                             raise Exception("DB 서비스 결과가 없습니다.")
                             
                except Exception as e:
                    print(f"보상 처리 중 에러 발생: {e}")
                    response_data = {
                        "status": "success",
                        "message": "훈련 성공! (보상 처리 중 오류 발생)", # 기본 성공 메시지
                        "base_reward": result.get("base_reward", {}),
                        "bonus_points": result.get("bonus_points", 0),
                    }
                
                await websocket.send_json(response_data)
                
                # 상태 초기화
                state = "READY"
                state_start_time = None
                last_detected_time = None
                print(f"[FSM_RESET] User {user_id} 상태 초기화 완료.")

    except WebSocketDisconnect:
        print(f"[FSM_WS] 사용자 {user_id} 연결 종료", flush=True)
    except Exception as e:
        print(f"[FSM_WS] 소켓 에러 발생: {e}", flush=True)
        try:
            await websocket.close()
        except:
            pass