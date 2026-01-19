import time
import asyncio
import os
from datetime import datetime
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.models.character import Character
from app.db.models.diary import Diary
from app.services import char_service
from app.db.database import AsyncSessionLocal
from app.ai_core.brain.graphs import get_character_response

class TrainingResultService:
    """
    훈련 결과 처리, DB 업데이트, LLM 통신 등을 담당하는 서비스 클래스
    """
    
    def __init__(self):
        self.last_llm_time = 0

    async def get_character_stats(self, db: AsyncSession, user_id: int):
        from sqlalchemy import select
        stmt = select(Character).where(Character.user_id == user_id)
        result = await db.execute(stmt)
        character_obj = result.scalar_one_or_none()
        
        char_stats = {"strength": 0, "happiness": 0}
        if character_obj:
            character = await char_service.get_character(db, character_obj.id)
            if character and character.stat:
                char_stats = {
                    "strength": character.stat.strength,
                    "intelligence": character.stat.intelligence,
                    "agility": character.stat.agility,
                    "happiness": character.stat.happiness,
                    "health": character.stat.health
                }
        return character_obj, char_stats

    async def trigger_llm_event(self, websocket, user_id: int, mode: str, action_type: str, 
                                is_success: bool = False, reward: dict = None, feedback: str = "", milestone: bool = False):
        """
        LLM에게 이벤트를 전달하고 캐릭터의 반응을 받아 소켓으로 전송
        """
        current_now = time.time()
        cooldown = 10 if not is_success else 0
        
        if current_now - self.last_llm_time < cooldown:
            return

        self.last_llm_time = current_now

        # Fire-and-forget wrapper
        async def _run_llm():
            try:
                async with AsyncSessionLocal() as db:
                    _, char_stats = await self.get_character_stats(db, user_id)

                    msg = await get_character_response(
                        user_id=user_id,
                        action_type=action_type,
                        current_stats=char_stats,
                        mode=mode,
                        is_success=is_success,
                        reward_info=reward or {},
                        feedback_detail=feedback,
                        milestone_reached=milestone
                    )
                    
                    from fastapi.websockets import WebSocketState
                    if websocket.client_state == WebSocketState.CONNECTED:
                        await websocket.send_json({
                            "char_message": msg,
                            "message": "AI: " + msg[:15] + "...",
                            "status": "keep"
                        })
                    else:
                        print(f"[LLM_SKIP] 소켓 연결 끊김 (User {user_id})")
            except Exception as ex:
                print(f"[LLM_ERROR] {ex}")

        asyncio.create_task(_run_llm())

    async def process_training_success(self, websocket, user_id: int, mode: str, result: dict, best_shot_data: bytes):
        """
        훈련 성공 시의 모든 후처리 작업 (DB 보상, 이미지 저장, 다이어리, LLM)
        """
        response_data = {}
        try:
            async with AsyncSessionLocal() as db:
                character_obj, _ = await self.get_character_stats(db, user_id)
                
                if not character_obj:
                    raise Exception("Character not found for user")
                    
                # 1. 스탯 업데이트
                service_result = await char_service.update_stats_from_yolo_result(db, character_obj.id, result)
                
                if service_result:
                    # 2. 베스트 샷 저장
                    best_shot_url = self._save_best_shot(user_id, best_shot_data)

                    updated_stat = service_result["stat"]
                    
                    # 3. LLM 호출 (직접 호출하여 응답 생성)
                    action_name = result.get("action_type", "action").replace("_", " ").title()
                    msg = await get_character_response(
                        user_id=user_id, 
                        action_type=action_name,
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
                        best_shot_url=best_shot_url
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
                        "best_shot_url": best_shot_url
                    }
                    
                    # 4. 다이어리 생성
                    if best_shot_url:
                        await self._create_diary_entry(db, user_id, best_shot_url, msg)
                        
                else:
                    raise Exception("DB Service Error")
                    
        except Exception as e:
            print(f"Error processing success: {e}")
            import traceback
            traceback.print_exc()
            response_data = {
                "status": "success",
                "message": "훈련 성공! (보상 오류)",
                "base_reward": result.get("base_reward", {}),
                "bonus_points": 0,
                "bbox": []
            }
        
        # 소켓 전송
        try:
             from fastapi.websockets import WebSocketState
             if websocket.client_state == WebSocketState.CONNECTED:
                await websocket.send_json(response_data)
        except Exception as ex:
             print(f"[Socket Error] {ex}")

    def _save_best_shot(self, user_id: int, img_data: bytes) -> str | None:
        if not img_data: return None
        try:
            today_str = datetime.now().strftime("%Y%m%d")
            upload_dir = f"uploads/{today_str}"
            os.makedirs(upload_dir, exist_ok=True)
            
            filename = f"best_shot_{user_id}_{int(time.time())}.jpg"
            filepath = f"{upload_dir}/{filename}"
            
            with open(filepath, "wb") as f:
                f.write(img_data)
                
            print(f"[BestShot] Saved: {filepath}")
            return f"/uploads/{today_str}/{filename}"
        except Exception as e:
            print(f"[BestShot] Save Error: {e}")
            return None

    async def _create_diary_entry(self, db: AsyncSession, user_id: int, image_url: str, content: str):
        try:
            diary_entry = Diary(
                user_id=user_id,
                image_url=image_url, 
                content=content, 
                tag="훈련인증",
                created_at=datetime.utcnow()
            )
            db.add(diary_entry)
            await db.commit() 
            print(f"[BestShot] Diary Uploaded with msg: {content[:20]}...")
        except Exception as e:
            print(f"[BestShot] Diary Error: {e}")
