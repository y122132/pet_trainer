from app.db.models.user import User
from sqlalchemy import select, or_, and_, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.models.friendship import Friendship
from app.db.models.chat_data import ChatMessage
from sqlalchemy.orm import selectinload

async def request_friend(db: AsyncSession, requester_id: int, receiver_id: int):
    # 중복 요청 체크
    stmt = select(Friendship).where(
        or_(
            and_(Friendship.requester_id == requester_id, Friendship.receiver_id == receiver_id),
            and_(Friendship.requester_id == receiver_id, Friendship.receiver_id == requester_id)
        )
    )
    result = await db.execute(stmt)
    existing = result.scalar_one_or_none()
    
    if existing:
        if existing.status == "accepted":
            return {"message": "Already friends", "status": "error"}
        if existing.requester_id == requester_id:
            return {"message": "Request already sent", "status": "pending"}
        return {"message": "You have a pending request from this user", "status": "needs_acceptance"}

    new_friendship = Friendship(requester_id=requester_id, receiver_id=receiver_id, status="pending")
    db.add(new_friendship)
    await db.commit()
    await db.refresh(new_friendship)
    return {"message": "Friend request sent", "status": "success", "id": new_friendship.id}

async def accept_friend(db: AsyncSession, receiver_id: int, requester_id: int):
    stmt = select(Friendship).where(
        Friendship.requester_id == requester_id,
        Friendship.receiver_id == receiver_id,
        Friendship.status == "pending"
    )
    result = await db.execute(stmt)
    friendship = result.scalar_one_or_none()
    
    if not friendship:
        return {"message": "No pending request found", "status": "error"}
        
    friendship.status = "accepted"
    await db.commit()
    return {"message": "Friend request accepted", "status": "success"}

async def get_friends(db: AsyncSession, user_id: int):
    stmt = select(Friendship).where(
        or_(Friendship.requester_id == user_id, Friendship.receiver_id == user_id),
        Friendship.status == "accepted"
    )
    result = await db.execute(stmt)
    friendships = result.scalars().all()
    
    friend_ids = [f.receiver_id if f.requester_id == user_id else f.requester_id for f in friendships]
            
    if not friend_ids:
        return []
        
    from app.db.models.character import Character, Stat
    
    # 상세 정보 조회
    stmt_users = (
        select(User, Character, Stat)
        .outerjoin(Character, Character.user_id == User.id)
        .outerjoin(Stat, Stat.character_id == Character.id)
        .where(User.id.in_(friend_ids))
    )
    result_users = await db.execute(stmt_users)
    rows = result_users.all()
    
    # 안 읽은 메시지 수 조회 (N+1 최적화)
    unread_stmt = (
        select(ChatMessage.sender_id, func.count(ChatMessage.id))
        .where(
            and_(
                ChatMessage.sender_id.in_(friend_ids),
                ChatMessage.receiver_id == user_id,
                ChatMessage.is_read == False
            )
        )
        .group_by(ChatMessage.sender_id)
    )
    result_unread = await db.execute(unread_stmt)
    unread_map = {row[0]: row[1] for row in result_unread.all()}
    
    friends_list = []
    for user, character, stat in rows:
        friends_list.append({
            "id": user.id,
            "username": user.username,
            "nickname": user.nickname,
            "level": stat.level if stat else 1,
            "last_active_at": f"{user.last_active_at.isoformat()}Z" if user.last_active_at else None,
            "pet_type": character.pet_type if character else "dog",
            "face_url": character.face_url if character else None,
            "unread_count": unread_map.get(user.id, 0)
        })
        
    return friends_list

async def get_pending_requests(db: AsyncSession, user_id: int):
    """나에게 온 친구 요청 목록을 사진/정보와 함께 반환 (안전한 버전)"""
    
    # 1. 나(receiver_id)에게 요청을 보낸 유저 정보를 Character와 함께 로드
    stmt = (
        select(User)
        .options(selectinload(User.character)) 
        .join(Friendship, Friendship.requester_id == User.id)
        .where(
            Friendship.receiver_id == user_id,
            Friendship.status == "pending"
        )
    )
    
    result = await db.execute(stmt)
    users = result.scalars().all()
    
    # 2. 결과가 없으면 빈 리스트 [] 반환 (None 객체 포함 리스트 X)
    if not users:
        return []
        
    # 3. 데이터 가공 (None 체크를 포함하여 에러 방지)
    return [
        {
            "id": u.id, 
            "username": u.username, 
            "nickname": u.nickname,
            "face_url": u.character.face_url if u.character else None,
            "pet_type": u.character.pet_type if u.character else "dog",
            "last_active_at": f"{u.last_active_at.isoformat()}Z" if u.last_active_at else None
        } 
        for u in users if u is not None
    ]