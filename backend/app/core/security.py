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
    """
    if not token:
        # [DEV] 개발 편의를 위해 토큰이 없어도 통과시킵니다.
        pass 
    
    # 임시: 토큰이 있으면 유효하다고 가정합니다.
    return True

# --- HTTP API 검증 함수 (Refactored) ---
from fastapi.security import OAuth2PasswordBearer
from fastapi import Depends

# 토큰을 얻어올 엔드포인트 URL 설정 (Swagger UI 인증에 사용)
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/v1/auth/login")

def verify_token(token: str) -> int:
    """
    JWT 토큰을 디코딩하고 유효성을 검증한 뒤 user_id를 반환합니다.
    """
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Could not validate credentials",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return int(user_id)
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

async def get_current_user_id(token: str = Depends(oauth2_scheme)) -> int:
    """
    FastAPI Dependency: 헤더에서 토큰을 추출하고 검증하여 user_id를 반환합니다.
    """
    return verify_token(token)