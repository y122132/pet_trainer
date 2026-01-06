from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import get_db
from app.core.security import get_current_user_id
from app.services import friend_service
from app.api.v1.chat import manager as chat_manager
import uuid

router = APIRouter()

@router.post("/invite")
async def invite_friend(
    friend_id: int, 
    current_user_id: int = Depends(get_current_user_id), 
    db: AsyncSession = Depends(get_db)
):
    """
    친구에게 배틀 초대장을 보냅니다.
    1. 친구 관계 확인
    2. 배틀 Room ID 생성
    3. 채팅 시스템 메시지로 초대장 전송
    """
    # 1. 친구 관계 확인
    friends = await friend_service.get_friends(db, current_user_id)
    is_friend = False
    friend_nickname = "Unknown"
    
    
    # 친구 확인
    for f in friends:
        if f["id"] == friend_id:
            is_friend = True
            friend_nickname = f["nickname"]
            break
            
    if not is_friend:
        pass

    room_id = str(uuid.uuid4())
    
    invite_payload = {
        "type": "BATTLE_INVITE",
        "room_id": room_id,
        "from_user_id": current_user_id,
        "message": "한판 붙자! (Battle Invitation)"
    }
    
    await chat_manager.send_personal_message(invite_payload, friend_id)
    
    return {"message": "Invite sent", "room_id": room_id}
