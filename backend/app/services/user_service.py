# backend/app/services/user_service.py
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from app.db.models.user import User
from app.core.security import get_password_hash, verify_password, create_access_token
from fastapi import HTTPException, status

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
    """
    로그인 비즈니스 로직: 자격 증명 확인 및 토큰 발급
    """
    # 1. 유저 조회 (캐릭터 정보도 함께 로딩)
    from sqlalchemy.orm import selectinload
    stmt = select(User).options(selectinload(User.character)).where(User.username == user_in.username)
    result = await db.execute(stmt)
    user = result.scalars().first()
    
    # 2. 비밀번호 검증
    if not user or not verify_password(user_in.password, user.password):
        return None # 검증 실패 시 None 반환 (라우터에서 예외 처리)
    
    # 3. JWT 토큰 생성
    # 3. JWT 토큰 생성
    # ACCESS_TOKEN_EXPIRE_MINUTES를 security 모듈에서 가져와야 함 (import 필요)
    from datetime import timedelta
    from app.core.security import ACCESS_TOKEN_EXPIRE_MINUTES
    
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": str(user.id)}, 
        expires_delta=access_token_expires
    )
    
    # 4. 캐릭터 존재 여부 확인 (Eager Loading 권장하지만 여기서는 간단히 로직 처리)
    # user.character가 로딩되지 않았을 수 있으므로 명시적 쿼리 또는 selectinload 사용
    # 여기서는 상단의 select 문을 수정하는 것이 가장 깔끔함.
    
    return {
        "access_token": access_token, 
        "token_type": "bearer", 
        "user_id": user.id,
        "username": user.username,
        "nickname": user.nickname,
        "character_id": user.character.id if user.character else None, # [New] 캐릭터 ID 반환
        "has_character": bool(user.character) # selectinload가 적용되었다면 바로 접근 가능
    }