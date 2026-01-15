# backend/app/api/v1/battle.py
import uuid
from app.db.database import get_db
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.security import get_current_user_id
from app.api.v1.chat import manager as chat_manager
from app.services import friend_service, user_service
from fastapi import APIRouter, Depends, HTTPException, status

router = APIRouter()

# --- 친구 초대 엔드포인트 ---
@router.post("/invite")
async def invite_friend(
    friend_id: int, # 초대할 친구의 고유 ID
    current_user_id: int = Depends(get_current_user_id), # 현재 로그인한 내 ID
    db: AsyncSession = Depends(get_db)
):
    friends = await friend_service.get_friends(db, current_user_id)
    if not any(f["id"] == friend_id for f in friends):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, 
            detail="친구가 아닌 유저에게는 초대장을 보낼 수 없습니다."
        )
    
    me = await user_service.get_user(db, current_user_id)
    my_nickname = me.nickname if me else "누군가"

    room_id = str(uuid.uuid4()) #두 유저가 만날 고유ID(UUID)를 생성
    
    print(f"\n[INVITE_DEBUG] =========================================")
    print(f"🚩 초대한 유저(나): {current_user_id}")
    print(f"🚩 초대받은 친구: {friend_id}")
    print(f"🚩 서버가 생성한 UUID: {room_id}")
    print(f"========================================================\n")
    
    invite_payload = {
        "type": "BATTLE_INVITE",
        "room_id": room_id,
        "from_user_id": current_user_id,
        "from_nickname": my_nickname,
        "message": f"⚔️ {my_nickname}님이 배틀 도전을 신청했습니다!"
    }
    
    try:
        success = await chat_manager.send_personal_message(invite_payload, friend_id)
        if not success:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, 
                detail="상대방이 현재 오프라인입니다."
            )
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ [초대 에러]: {e}")
        raise HTTPException(status_code=500, detail="알림 전송 중 서버 오류")

    return {
        "status": "success",
        "room_id": room_id
    }
