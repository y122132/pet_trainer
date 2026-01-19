# backend/app/main.py
import os
from pathlib import Path
from fastapi import FastAPI
from requests import Request
from dotenv import load_dotenv
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware


# 현재 파일(main.py)의 위치: backend/app/main.py
# 루트 .env 위치: backend/app/../../.env -> Project Root
env_path = Path(__file__).resolve().parent.parent.parent / ".env"
load_dotenv(dotenv_path=env_path)

from app.api.v1.routers import api_router
from app.sockets.analysis_socket import router as websocket_router
from app.sockets.battle_socket import router as battle_router
from app.db.database import init_db
from app.ai_core.vision import detector

from app.db.database_redis import RedisManager # 추가

# Admin
from sqladmin import Admin
from app.db.database import engine
from app.admin_panel import UserAdmin, CharacterAdmin, StatAdmin, ActionLogAdmin, DiaryAdmin, DiaryLikeAdmin, NoticeAdmin


app = FastAPI(title="PetTrainer API")

# Mount the 'uploads' directory to serve static files
# This should be placed before the routers if there's any path conflict.
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")


# CORS (Cross-Origin Resource Sharing) 미들웨어 설정
# 프론트엔드(Flutter/Web)가 다른 도메인에서 API를 호출할 수 있도록 허용합니다.

origins_env = os.getenv("ALLOWED_ORIGINS", "*")
origins = [origin.strip() for origin in origins_env.split(",")]

if "origins" not in locals() or origins == ["*"]:
    # [*] Wildcard with credentials is invalid. Use regex for localhost dev.
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=r"https?://(localhost|127\.0\.0\.1|10\.0\.2\.2|192\.168\.\d+\.\d+)(:\d+)?",
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
else:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

# 서버 시작 시 실행되는 이벤트 핸들러
@app.on_event("startup")
async def on_startup():
    """
    서버가 시작될 때 초기화 작업을 수행합니다.
    1. DB 초기화 (테이블 생성 및 기본 데이터 시딩)
    2. AI 모델 프리로딩 (첫 요청 지연 방지)
    """
    await init_db()
    
    # YOLO 모델을 메모리에 미리 로드합니다.
    # 이렇게 하면 첫 번째 사용자 요청 시 모델 로딩으로 인한 딜레이가 발생하지 않습니다.
    detector.load_models()

# 라우터 등록
# REST API와 WebSocket 엔드포인트를 메인 앱에 연결합니다.
app.include_router(api_router)
app.include_router(websocket_router, prefix="/v1")
app.include_router(battle_router, prefix="/v1")

# Admin Panel Setup
from app.admin_auth import authentication_backend

admin = Admin(app, engine, authentication_backend=authentication_backend)
admin.add_view(UserAdmin)
admin.add_view(CharacterAdmin)
admin.add_view(StatAdmin)
admin.add_view(ActionLogAdmin)
admin.add_view(DiaryAdmin)
admin.add_view(DiaryLikeAdmin)
admin.add_view(NoticeAdmin)

@app.get("/")
async def root():
    """
    서버 상태 확인용 루트 엔드포인트입니다.
    """
    return {"message": "Welcome to PetTrainer API"}

@app.on_event("shutdown")
async def on_shutdown():
    """
    서버 종료 시 리소스를 안전하게 해제합니다.
    """
    await RedisManager.close() # Redis 연결 풀 닫기

@app.middleware("http")
async def update_last_active(request: Request, call_next):
    # Fire & Forget: 토큰이 있으면 last_active_at 갱신 (에러 무시)
    try:
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1]
            
            # 필요한 모듈 임포트 (순환 참조 방지 및 Scope 격리)
            from jose import jwt
            from app.core.security import SECRET_KEY, ALGORITHM
            from app.db.models.user import User
            from app.db.database import AsyncSessionLocal
            from app.db.database_redis import RedisManager
            from sqlalchemy.future import select
            from datetime import datetime, timezone

            # 토큰 디코딩
            payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
            user_id = payload.get("sub")

            if user_id:
                # [Redis Throttling] 5분에 1번만 DB 업데이트
                redis = RedisManager.get_client()
                cooldown_key = f"user:{user_id}:active_cooldown"
                
                # 키가 존재하면(쿨타임 중이면) DB 업데이트 건너뜀
                if not await redis.get(cooldown_key):
                    async with AsyncSessionLocal() as db:
                        # 유저 조회
                        result = await db.execute(select(User).where(User.id == int(user_id)))
                        user = result.scalars().first()
                        
                        if user:
                            # 현재 시간(UTC)으로 갱신
                            user.last_active_at = datetime.now(timezone.utc).replace(tzinfo=None)
                            await db.commit()
                            
                            # 쿨타임 설정 (300초 = 5분)
                            await redis.set(cooldown_key, "1", ex=300)

    except Exception:
        # 미들웨어 로직 실패가 API 응답을 막지 않도록 예외 무시
        pass

    response = await call_next(request)
    return response