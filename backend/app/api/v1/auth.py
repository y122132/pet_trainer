# backend/app/api/v1/auth.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from app.db.database import get_db
from app.db.models.user import User
from app.core.security import get_password_hash, verify_password, create_access_token
from pydantic import BaseModel

router = APIRouter()

# 입출력 데이터 모델 (Schemas)
class UserAuth(BaseModel):
    username: str
    password: str

@router.post("/register")
async def register(user_in: UserAuth, db: AsyncSession = Depends(get_db)):
    # 1. 중복 유저 확인
    result = await db.execute(select(User).where(User.username == user_in.username))
    if result.scalars().first():
        raise HTTPException(status_code=400, detail="이미 존재하는 아이디입니다.")
    
    # 2. 유저 생성
    new_user = User(
        username=user_in.username,
        password=get_password_hash(user_in.password)
    )
    db.add(new_user)
    await db.commit()
    return {"message": "회원가입 성공"}

@router.post("/login")
async def login(user_in: UserAuth, db: AsyncSession = Depends(get_db)):
    # 1. 유저 찾기
    result = await db.execute(select(User).where(User.username == user_in.username))
    user = result.scalars().first()
    
    # 2. 비번 검증
    if not user or not verify_password(user_in.password, user.password):
        raise HTTPException(status_code=401, detail="아이디 또는 비밀번호가 틀렸습니다.")
    
    # 3. 토큰 발급
    access_token = create_access_token(data={"sub": str(user.id)})
    return {"access_token": access_token, "token_type": "bearer", "user_id": user.id}