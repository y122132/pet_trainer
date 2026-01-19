# backend/app/services/chat_service.py
import json
import logging
from app.db.database import AsyncSessionLocal
from app.db.models.chat_data import ChatMessage
from app.db.database_redis import RedisManager
from sqlalchemy.future import select

logger = logging.getLogger(__name__)

class ChatService:
    @staticmethod
    async def process_message(sender_id: int, sender_nickname: str, raw_data: str):
        """
        웹소켓으로 받은 메시지를 처리합니다.
        1. JSON 파싱
        2. DB 저장 (별도 세션 사용)
        3. Redis 알림 발행
        """
        try:
            message_json = json.loads(raw_data)
            
            # [Heartbeat] PING 메시지 처리
            if message_json.get("type") == "PING":
                # logger.debug(f"[ChatService] Received PING from User {sender_id}")
                return

            # 필수 필드 확인
            if "to_user_id" not in message_json or "message" not in message_json:
                logger.warning(f"[ChatService] 필수 필드 누락 (User {sender_id}): {message_json.keys()}")
                return

            receiver_id = int(message_json.get("to_user_id"))
            content = message_json.get("message")
        except (json.JSONDecodeError, ValueError, TypeError) as e:
            logger.error(f"[ChatService] 메시지 파싱 에러 (User {sender_id}): {e}")
            return

        # DB 세션을 이 블록 안에서만 사용하고 즉시 닫음
        async with AsyncSessionLocal() as db:
            try:
                new_msg = ChatMessage(
                    sender_id=sender_id,
                    receiver_id=receiver_id,
                    message=content
                )
                db.add(new_msg)
                await db.commit()
                await db.refresh(new_msg)
                created_at = new_msg.created_at
            except Exception as e:
                logger.error(f"[ChatService] DB 저장 실패 (User {sender_id} -> {receiver_id}): {e}")
                await db.rollback()
                return

        # 알림 발행 (DB 세션 종료 후 수행)
        notification_payload = {
            "type": "CHAT_NOTIFICATION",
            "from_user_id": sender_id,
            "sender_nickname": sender_nickname,
            "message": content,
            "created_at": created_at.isoformat()
        }

        try:
            await RedisManager.publish_chat_notification(receiver_id, notification_payload)
        except Exception as e:
            logger.error(f"[ChatService] Redis 발행 실패 (User {sender_id} -> {receiver_id}): {e}")
