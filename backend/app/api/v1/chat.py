# backend/app/api/v1/chat.py
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from typing import Dict
import json

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
    
class ChatManager:
    def __init__(self):
        # 현재 접속 중인 유저 {user_id: websocket_object}
        self.active_connections: Dict[int, WebSocket] = {}

    async def connect(self, user_id: int, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[user_id] = websocket
        print(f"[CHAT] 유저 {user_id} 연결됨. 현재 접속자: {list(self.active_connections.keys())}")

    def disconnect(self, user_id: int):
        if user_id in self.active_connections:
            del self.active_connections[user_id]
            print(f"[CHAT] 유저 {user_id} 연결 끊김.")

    async def send_personal_message(self, message: dict, receiver_id: int):
        """특정 유저에게 메시지 전송"""
        if receiver_id in self.active_connections:
            await self.active_connections[receiver_id].send_json(message)
        else:
            print(f"[CHAT] 유저 {receiver_id}는 현재 오프라인입니다.")

manager = ChatManager()

@router.websocket("/ws/chat/{user_id}")
async def chat_endpoint(websocket: WebSocket, user_id: int):
    await manager.connect(user_id, websocket)
    try:
        while True:
            # 1. 클라이언트로부터 메시지 수신 (JSON 형식)
            # 형식 예: {"to_user_id": 2, "message": "안녕, 반가워!"}
            data = await websocket.receive_text()
            message_json = json.loads(data)
            
            receiver_id = int(message_json.get("to_user_id"))
            content = message_json.get("message")

            # 2. 상대방에게 보낼 패이로드 구성
            payload = {
                "from_user_id": user_id,
                "message": content
            }

            # 3. 상대방에게 전달
            await manager.send_personal_message(payload, receiver_id)
            
    except WebSocketDisconnect:
        manager.disconnect(user_id)
    except Exception as e:
        print(f"[CHAT] 에러 발생: {e}")
        manager.disconnect(user_id)