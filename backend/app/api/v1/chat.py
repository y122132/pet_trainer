from typing import Dict

class ChatManager:
    def __init__(self):
        # 유저 ID를 키로 하여 연결된 소켓 저장
        self.active_connections: Dict[int, WebSocket] = {}

    async def connect(self, user_id: int, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[user_id] = websocket

    def disconnect(self, user_id: int):
        if user_id in self.active_connections:
            del self.active_connections[user_id]

    async def send_personal_message(self, message: str, receiver_id: int):
        # 특정 유저에게만 메시지 전송 (1:1 채팅)
        if receiver_id in self.active_connections:
            await self.active_connections[receiver_id].send_text(message)

chat_manager = ChatManager()

@router.websocket("/ws/chat/{user_id}")
async def chat_endpoint(websocket: WebSocket, user_id: int):
    await chat_manager.connect(user_id, websocket)
    try:
        while True:
            data = await websocket.receive_json() # { "receiver_id": 2, "msg": "안녕" }
            # 메시지 처리 및 상대방에게 전달
            await chat_manager.send_personal_message(data['msg'], data['receiver_id'])
    except WebSocketDisconnect:
        chat_manager.disconnect(user_id)