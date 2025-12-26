# backend/app/api/v1/auth.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import get_db
from app.services import user_service  # 1단계에서 작성한 서비스 임포트
from pydantic import BaseModel, Field

router = APIRouter()

# 데이터 모델(Schema)은 라우터에서 유지
class UserCreate(BaseModel):
    username: str
    nickname: str
    password: str = Field(..., max_length=72)

class UserLogin(BaseModel):
    username: str
    password: str

@router.post("/register")
async def register(user_in: UserCreate, db: AsyncSession = Depends(get_db)):
    """회원가입 엔드포인트: 서비스로 로직 위임"""
    return await user_service.register_user(db, user_in)

@router.post("/login")
async def login(user_in: UserLogin, db: AsyncSession = Depends(get_db)):
    """로그인 엔드포인트: 서비스로부터 인증 결과 수신"""
    auth_result = await user_service.authenticate_user(db, user_in)
    
    if not auth_result:
        raise HTTPException(status_code=401, detail="아이디 또는 비밀번호가 틀렸습니다.")
        
    return auth_result