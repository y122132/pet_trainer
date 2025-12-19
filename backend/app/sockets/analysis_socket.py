from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool
from app.ai_core.vision import detector
from app.services import char_service
from app.db.database import AsyncSessionLocal
from app.core.pet_constants import PET_CLASS_MAP
import json

router = APIRouter()

@router.websocket("/ws/analysis/{user_id}")
async def analysis_endpoint(websocket: WebSocket, user_id: int, mode: str = "playing", pet_type: str = "none", difficulty: str = "easy"):
    """
    실시간 분석을 위한 웹소켓 엔드포인트입니다.
    - user_id: 사용자 ID
    - mode: 훈련 모드 ('playing', 'feeding', 'interaction')
    - pet_type: 반려동물 종류 ('dog', 'cat')
    - difficulty: 난이도 ('easy', 'hard')
    """
    try:
        print(f"[DEBUG_WS] 연결 시도: 사용자 {user_id}, 모드 {mode}, 펫 {pet_type}, 난이도 {difficulty}", flush=True)
        await websocket.accept()
        print(f"[DEBUG_WS] 연결 수락됨", flush=True)
    except Exception as e:
        print(f"[DEBUG_WS] 연결 수락 실패: {e}", flush=True)
        return
    
    # 반려동물 종류를 YOLO Class ID로 변환 (기본값: 0=사람)
    # pet_constants.py에 정의된 매핑 사용
    target_class_id = PET_CLASS_MAP.get(pet_type, 0)
        
    try:
        while True:
            # 1. Base64 이미지 데이터 수신 (프론트엔드에서 텍스트로 전송됨)
            base64_image = await websocket.receive_text()
            
            # 2. YOLO 추론 실행
            # run_in_threadpool을 사용하여 메인 스레드(Event Loop)가 차단되지 않도록 함
            result = await run_in_threadpool(detector.process_frame, base64_image, mode, target_class_id, difficulty)
            
            # 3. 응답 데이터 구성
            response_data = {
                "status": "success" if result.get("success") else "fail",
                "message": result.get("message", ""),
                "keypoints": result.get("keypoints", []),   # 사람 스켈레톤 (교감 모드 시)
                "bbox": result.get("bbox", []),             # 반려동물 바운딩 박스
                "image_width": result.get("width", 0),
                "image_height": result.get("height", 0),
                "feedback": result.get("feedback_message", ""), # 사용자 피드백 (예: 더 가까이)
                "base_reward": result.get("base_reward", {}),   # 기본 보상 {stat_type, value}
                "bonus_points": result.get("bonus_points", 0),  # 추가 점수
                "count": 0  # 일일 수행 횟수 (DB 업데이트 후 갱신됨)
            }

            if result.get("success"):
                # 성공 시에만 DB 업데이트
                async with AsyncSessionLocal() as db:
                    service_result = await char_service.update_stats_from_yolo_result(
                        db, 
                        user_id, # 현재는 user_id와 char_id를 1:1로 가정
                        result
                    )
                    
                    if service_result:
                        updated_stat = service_result["stat"]
                        daily_count = service_result["daily_count"]
                        milestone = service_result["milestone_reached"]
                        
                        response_data["count"] = daily_count 
                        response_data["strength"] = updated_stat.strength
                        response_data["exp"] = updated_stat.exp
                        
                        # (선택) LLM 캐릭터 대화 생성
                        # 성능 이슈가 있다면 이 부분을 비동기 Task로 분리하거나 생략 가능
                        try:
                            from app.ai_core.brain.graphs import get_character_response
                            
                            current_stats = {
                                "strength": updated_stat.strength,
                                "health": updated_stat.health,
                                "happiness": updated_stat.happiness
                            }
                            
                            action_name = result.get("action_type", "action")
                            display_name = action_name.replace("_", " ").title()
                            feedback = result.get("feedback_message", "")

                            ai_message = await get_character_response(
                                action_type=f"{display_name}", 
                                current_stats=current_stats,
                                mode=mode,
                                is_success=True,
                                reward_info={
                                    "stat_type": result.get("base_reward", {}).get("stat_type"),
                                    "value": result.get("base_reward", {}).get("value"),
                                    "bonus_points": result.get("bonus_points", 0)
                                },
                                feedback_detail=feedback,
                                daily_count=daily_count,
                                milestone_reached=milestone
                            )
                            response_data["message"] = ai_message
                            
                        except Exception as e:
                            print(f"LLM 오류 (기본 메시지 사용): {e}")
                            # fallback: detector 메시지 그대로 사용

            else:
                # 실패 케이스: 필요하다면 격려 메시지 생성 (여기서는 생략하고 detector 메시지 사용)
                pass

            # 4. 클라이언트로 결과 전송
            await websocket.send_json(response_data)
            
    except WebSocketDisconnect:
        print(f"[DEBUG_WS] 사용자 {user_id} 연결 종료", flush=True)
    except Exception as e:
        print(f"[DEBUG_WS] 소켓 에러 발생: {e}", flush=True)
        try:
            await websocket.close()
        except:
            pass