# backend/app/services/user_service.py
from app.db.models.user import User
from sqlalchemy.future import select
from datetime import timedelta, datetime, timezone
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.security import get_password_hash, verify_password, create_access_token

async def register_user(db: AsyncSession, user_in):
    """
    회원가입 비즈니스 로직: 아이디 중복 확인 및 유저 생성
    """
    # 1. 아이디 중복 확인
    result = await db.execute(select(User).where(User.username == user_in.username))
    if result.scalars().first():
        raise HTTPException(status_code=400, detail="이미 존재하는 아이디입니다.")
    
    # 2. 새로운 유저 객체 생성 및 비밀번호 해싱
    new_user = User(
        username=user_in.username,
        nickname=user_in.nickname,
        password=get_password_hash(user_in.password)
    )
    
    # 3. DB 저장
    db.add(new_user)
    await db.commit()
    await db.refresh(new_user) # 저장된 객체 최신화
    return {"message": "회원가입 성공"}

async def authenticate_user(db: AsyncSession, user_in):
    # 1. 유저 조회 (캐릭터 정보도 함께 로딩)
    from sqlalchemy.orm import selectinload
    stmt = select(User).options(selectinload(User.character)).where(User.username == user_in.username)
    result = await db.execute(stmt)
    user = result.scalars().first()
    
    # 2. 비밀번호 검증
    if not user or not verify_password(user_in.password, user.password):
        return None # 검증 실패 시 None 반환 (라우터에서 예외 처리)
    


    user.last_active_at = datetime.now(timezone.utc).replace(tzinfo=None)
    
    await db.commit()
    await db.refresh(user)

    # 3. JWT 토큰 생성
    # ACCESS_TOKEN_EXPIRE_MINUTES를 security 모듈에서 가져와야 함 (import 필요)
    from app.core.security import ACCESS_TOKEN_EXPIRE_MINUTES
    
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": str(user.id)}, 
        expires_delta=access_token_expires
    )

    # 캐릭터 존재 여부 확인

    return {
        "access_token": access_token, 
        "token_type": "bearer", 
        "user_id": user.id,
        "username": user.username,
        "nickname": user.nickname,
        "character_id": user.character.id if user.character else None,
        "has_character": bool(user.character), 
        "last_active_at": f"{user.last_active_at.isoformat()}Z" if user.last_active_at else None,
    }

async def get_all_users(db: AsyncSession, query: str = None):
    """모든 사용자 목록을 조회합니다. (검색어 포함)"""
    stmt = select(User)
    if query:
        from sqlalchemy import or_
        stmt = stmt.where(or_(User.username.contains(query), User.nickname.contains(query)))
        
    result = await db.execute(stmt)
    users = result.scalars().all()
    return [
        {"id": u.id, "username": u.username, "nickname": u.nickname}
        for u in users
    ]

async def get_user(db: AsyncSession, user_id: int):
    result = await db.execute(select(User).where(User.id == user_id))
    return result.scalar_one_or_none()