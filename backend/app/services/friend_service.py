from app.db.models.user import User
from sqlalchemy import select, or_, and_, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.models.friendship import Friendship
from app.db.models.chat_data import ChatMessage

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
    
    friend_ids = []
    for f in friendships:
        if f.requester_id == user_id:
            friend_ids.append(f.receiver_id)
        else:
            friend_ids.append(f.requester_id)
            
    if not friend_ids:
        return []
        
    from app.db.models.character import Character, Stat
    
    stmt_users = (
        select(User, Character, Stat)
        .outerjoin(Character, Character.user_id == User.id)
        .outerjoin(Stat, Stat.character_id == Character.id)
        .where(User.id.in_(friend_ids))
    )
    result_users = await db.execute(stmt_users)
    rows = result_users.all()
    
    friends_list = []
    for user, character, stat in rows:
        unread_stmt = select(func.count(ChatMessage.id)).where(
            and_(
                ChatMessage.sender_id == user.id,      # 보낸 이: 친구
                ChatMessage.receiver_id == user_id,    # 받는 이: 나
                ChatMessage.is_read == False           # 읽지 않음
            )
        )
        unread_count = await db.scalar(unread_stmt) or 0

        friend_data = {
            "id": user.id,
            "username": user.username,
            "nickname": user.nickname,
            "level": stat.level if stat else 1, # [Fix] Access level from Stat
            "pet_type": character.pet_type if character else "dog",
            "unread_count": unread_count
        }
        friends_list.append(friend_data)
        
    return friends_list

async def get_pending_requests(db: AsyncSession, user_id: int):
    # 나에게 온 요청 중 status='pending'인 것
    stmt = select(Friendship).where(
        Friendship.receiver_id == user_id,
        Friendship.status == "pending"
    )
    result = await db.execute(stmt)
    friendships = result.scalars().all()
    
    if not friendships:
        return []
        
    requester_ids = [f.requester_id for f in friendships]
    user_stmt = select(User).where(User.id.in_(requester_ids))
    user_res = await db.execute(user_stmt)
    users = user_res.scalars().all()
    
    return [{"id": u.id, "username": u.username, "nickname": u.nickname} for u in users]
