from passlib.context import CryptContext
import os
from datetime import datetime, timedelta
from jose import jwt, JWTError
from typing import Optional
from fastapi import WebSocket, HTTPException, status

# 1. 비밀번호 암호화 설정 (network 브랜치 로직)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# JWT 설정
# JWT 설정
SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key-very-secret") 
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 1일

# --- 인증 관련 함수 (network 브랜치 로직) ---

def get_password_hash(password: str) -> str:
    """비밀번호를 해시화합니다."""
    return pwd_context.hash(password[:72])

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """평문 비밀번호와 해시된 비밀번호를 비교합니다."""
    return pwd_context.verify(plain_password, hashed_password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    """JWT 액세스 토큰을 생성합니다."""
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=15))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

# --- 웹소켓 검증 함수 (develop 브랜치 구조 유지) ---

async def verify_websocket_token(websocket: WebSocket, token: Optional[str]):
    """
    WebSocket 연결 시 토큰을 검증합니다.
    현재는 develop 브랜치의 방침에 따라 구조만 유지하며 모든 토큰을 허용합니다.
    추후 위의 SECRET_KEY와 ALGORITHM을 사용하여 JWT 검증 로직을 구현할 수 있습니다.
    """
    if not token:
        # [DEV] 개발 편의를 위해 토큰이 없어도 통과시킵니다.
        pass 
    
    # 임시: 토큰이 있으면 유효하다고 가정합니다.
    return True