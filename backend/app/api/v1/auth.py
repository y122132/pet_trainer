# backend/app/api/v1/auth.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import get_db
from app.services import user_service, friend_service # Friend Service 임포트
from pydantic import BaseModel, Field
from app.core.security import get_current_user_id # [Refactored] Use centralized logic

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

@router.get("/users")
async def get_users(query: str = None, db: AsyncSession = Depends(get_db)):
    """전체 유저 목록 조회 (검색 기능 포함)"""
    return await user_service.get_all_users(db, query)

# --- Friend API Endpoints ---

@router.post("/friends/request/{friend_id}")
async def request_friend(friend_id: int, current_user_id: int = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)):
    """친구 요청 보내기"""
    if friend_id == current_user_id:
        raise HTTPException(status_code=400, detail="Cannot add yourself as a friend")
    return await friend_service.request_friend(db, current_user_id, friend_id)

@router.post("/friends/accept/{friend_id}")
async def accept_friend(friend_id: int, current_user_id: int = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)):
    """친구 요청 수락하기 (friend_id는 요청을 보낸 사람의 ID)"""
    return await friend_service.accept_friend(db, current_user_id, friend_id)

@router.get("/friends")
async def get_friends(current_user_id: int = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)):
    """내 친구 목록 조회"""
    return await friend_service.get_friends(db, current_user_id)

@router.get("/friends/pending")
async def get_pending_requests(current_user_id: int = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)):
    """나에게 온 대기 중인 친구 요청 조회"""
    return await friend_service.get_pending_requests(db, current_user_id)