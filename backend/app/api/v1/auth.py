# backend/app/api/v1/auth.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from app.db.database import get_db
from app.db.models.user import User
from app.core.security import get_password_hash, verify_password, create_access_token
from pydantic import BaseModel, Field
from typing import List

router = APIRouter()

# 입출력 데이터 모델 (Schemas)
# 1. 회원가입 시 받을 데이터
class UserCreate(BaseModel):
    username: str
    nickname: str
    password: str = Field(..., max_length=72)

# 2. 로그인 시 받을 데이터 (닉네임 제외)
class UserLogin(BaseModel):
    username: str
    password: str

# 3. 유저 목록 응답 시 보낼 데이터 (비밀번호 제외)
class UserListItem(BaseModel):
    id: int
    username: str
    nickname: str

    class Config:
        from_attributes = True # ORM 객체를 자동으로 변환하기 위함

# ... (상단 import 부분은 동일)

@router.post("/register")
async def register(user_in: UserCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.username == user_in.username))
    if result.scalars().first():
        raise HTTPException(status_code=400, detail="이미 존재하는 아이디입니다.")
    
    new_user = User(
        username=user_in.username,
        nickname=user_in.nickname,
        password=get_password_hash(user_in.password)
    )
    db.add(new_user)
    await db.commit()
    return {"message": "회원가입 성공"}

@router.post("/login")
# 1. 여기를 UserCreate에서 UserLogin으로 변경! (이것 때문에 nickname 필드 에러가 났던 겁니다)
async def login(user_in: UserLogin, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.username == user_in.username))
    user = result.scalars().first()
    
    if not user or not verify_password(user_in.password, user.password):
        raise HTTPException(status_code=401, detail="아이디 또는 비밀번호가 틀렸습니다.")
    
    access_token = create_access_token(data={"sub": str(user.id)})
    return {"access_token": access_token, "token_type": "bearer", "user_id": user.id}

@router.get("/users", response_model=List[UserListItem])
async def get_users(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User))
    users = result.scalars().all()
    
    # 2. nickname을 포함해서 반환해야 합니다 (UserListItem 모델 규격 맞추기)
    return [
        {
            "id": u.id, 
            "username": u.username, 
            "nickname": u.nickname if u.nickname else u.username # 닉네임 없으면 아이디로 대체
        } 
        for u in users
    ]