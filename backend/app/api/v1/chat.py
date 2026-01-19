# backend/app/api/v1/chat.py
import json
import asyncio
from typing import Dict
from app.db.database import get_db, AsyncSessionLocal
from app.services import user_service
from app.db.models.chat_data import ChatMessage
from app.db.database_redis import RedisManager
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import and_, or_, update
from sqlalchemy.future import select
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends

router = APIRouter()

# [추가] Swagger UI에 chat 섹션을 나타나게 하기 위한 상태 확인 엔드포인트
@router.get("/status", tags=["chat"])
async def get_chat_status():
    """
    채팅 서버의 현재 상태를 확인합니다.
    """
    return {
        "status": "online",
        "active_connections": len(manager.active_connections)
    }
    

# 로깅 설정
import logging
from app.services.chat_service import ChatService

logger = logging.getLogger(__name__)

class ChatManager:
    def __init__(self):
        self.active_connections: Dict[int, dict] = {}
        self.notification_tasks: Dict[int, asyncio.Task] = {}

    async def connect(self, user_id: int, nickname: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[user_id] = {
            "socket": websocket,
            "nickname": nickname
        }
        logger.info(f"[CHAT] {nickname}({user_id}) 연결됨.")

    async def disconnect(self, user_id: int):
        if user_id in self.active_connections:
            del self.active_connections[user_id]
            await RedisManager.set_user_offline(user_id)
        
            await self.broadcast({
                "type": "USER_STATUS",
                "user_id": user_id,
                "online": False
            })
            logger.info(f"[CHAT] 유저 {user_id} 연결 끊김.")
            
        # [Fix] 연결 끊김 시 리스너 태스크도 확실하게 정리
        await self.cancel_notification_task(user_id)

    async def register_notification_task(self, user_id: int, task: asyncio.Task):
        # 기존에 돌고 있는 태스크가 있다면 취소 (좀비 방지)
        await self.cancel_notification_task(user_id)
        self.notification_tasks[user_id] = task
        logger.debug(f"[CHAT] 유저 {user_id}의 새 알림 리스너 등록됨.")

    async def cancel_notification_task(self, user_id: int):
        task = self.notification_tasks.pop(user_id, None) 
        if task:
            if not task.done():
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
            logger.debug(f"[CHAT] 유저 {user_id}의 알림 리스너가 안전하게 제거되었습니다.")

    async def broadcast(self, payload: dict):
        message = json.dumps(payload, ensure_ascii=False)
        for uid in list(self.active_connections.keys()):
            try:
                if uid in self.active_connections:
                    await self.active_connections[uid]["socket"].send_text(message)
            except Exception as e:
                logger.warning(f"[CHAT] Broadcast error to {uid}: {e}")

    def get_nickname(self, user_id: int) -> str:
        user_info = self.active_connections.get(user_id)
        return user_info["nickname"] if user_info else f"User_{user_id}"

manager = ChatManager()

@router.websocket("/ws/chat/{user_id}")
async def chat_endpoint(websocket: WebSocket, user_id: int):
    # 주의: 여기서 get_db를 Depends로 받지 않음. 
    # 초기 유저 확인을 위해서만 일회성으로 세션을 열거나, 
    # 혹은 닉네임만 필요하다면 간단히 처리할 수도 있습니다.
    # 여기서는 닉네임 조회를 위해 일회성 세션을 사용합니다.
    
    nickname = f"User_{user_id}"
    async with AsyncSessionLocal() as db:
        user = await user_service.get_user(db, user_id)
        if user:
            nickname = user.nickname

    await manager.connect(user_id, nickname, websocket)
    await RedisManager.set_user_online(user_id)

    online_members = []
    for uid in list(manager.active_connections.keys()):
        online_members.append(uid)
    
    await websocket.send_text(json.dumps({
        "type": "INITIAL_ONLINE_LIST",
        "user_ids": online_members
    }))

    await manager.broadcast({
        "type": "USER_STATUS",
        "user_id": user_id,
        "online": True
    })

    # [Fix] 리스너 태스크를 매니저에 등록하여 관리
    notification_task = asyncio.create_task(listen_to_notifications(websocket, user_id))
    await manager.register_notification_task(user_id, notification_task)

    try:
        while True:
            data = await websocket.receive_text()
            # 서비스 계층 호출 (내부에서 DB 세션 관리)
            await ChatService.process_message(user_id, nickname, data)
            
    except WebSocketDisconnect:
        logger.info(f"[CHAT] 유저 {user_id} 연결 종료 (WebSocketDisconnect)")
    except Exception as e:
        logger.error(f"[CHAT] 유저 {user_id} 연결 중 치명적 에러: {e}")
    finally:
        await RedisManager.set_user_offline(user_id)
        await manager.disconnect(user_id)
        

async def listen_to_notifications(websocket: WebSocket, user_id: int):
    """Redis에서 나에게 온 알림이 있는지 계속 듣고 있다가 소켓으로 쏴주는 역할"""
    redis_client = RedisManager.get_client()
    pubsub = redis_client.pubsub()
    await pubsub.subscribe(f"user_notify_{user_id}")
    
    try:
        async for message in pubsub.listen():
            if message['type'] == 'message':
                # Redis 채널에 메시지가 뜨면 즉시 웹소켓으로 전송
                await websocket.send_text(message['data'])
    except Exception as e:
        print(f"Notification Error: {e}")
    finally:
        await pubsub.unsubscribe(f"user_notify_{user_id}")

@router.get("/history/{other_user_id}", tags=["chat"])
async def get_chat_history(
    other_user_id: int, 
    current_user_id: int, # 실제로는 Depends(get_current_user)를 쓰시는게 보안상 좋습니다.
    db: AsyncSession = Depends(get_db)
):

    query = select(ChatMessage).where(
        or_(
            and_(ChatMessage.sender_id == current_user_id, ChatMessage.receiver_id == other_user_id),
            and_(ChatMessage.sender_id == other_user_id, ChatMessage.receiver_id == current_user_id)
        )
    ).order_by(ChatMessage.created_at.asc()).limit(50)

    result = await db.execute(query)
    messages = result.scalars().all()

    return [
        {
            "from_user_id": m.sender_id,
            "message": m.message,
            "created_at": m.created_at.isoformat()
        } for m in messages
    ]

@router.post("/read/{sender_id}", tags=["chat"])
async def mark_messages_as_read(
    sender_id: int, 
    current_user_id: int, 
    db: AsyncSession = Depends(get_db)
):
    
    # 상대방이 나에게 보낸(receiver_id == 나) 메시지 중 안 읽은 것들을 True로 변경
    query = update(ChatMessage).where(
        and_(
            ChatMessage.sender_id == sender_id,
            ChatMessage.receiver_id == current_user_id,
            ChatMessage.is_read == False
        )
    ).values(is_read=True)
    
    await db.execute(query)
    await db.commit()
    return {"status": "success"}