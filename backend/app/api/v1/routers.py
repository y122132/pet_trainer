# backend/app/api/v1/routers.py
from fastapi import APIRouter
# [수정] 모든 도메인 라우터를 임포트합니다.
from app.api.v1 import chat, auth, characters 

# 메인 API 라우터 (/v1)
api_router = APIRouter(prefix="/v1")

# --- 각 기능별 라우터 통합 ---

# 1. 인증 라우터 (network 브랜치 기능)
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])

# 2. 채팅 라우터 (network 브랜치 기능)
api_router.include_router(chat.router, prefix="/chat", tags=["chat"])

# 3. 캐릭터 라우터 (분리된 신규 파일 연결)
api_router.include_router(characters.router)

# 4. 배틀 라우터 (초대 기능 등 HTTP API)
from app.api.v1 import battle
api_router.include_router(battle.router, prefix="/battle", tags=["battle"])

# [정리] 기존의 임시 user_router는 auth.py가 역할을 대신하므로 삭제했습니다.