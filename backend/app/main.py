from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os
from dotenv import load_dotenv

from pathlib import Path

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


app = FastAPI(title="PetTrainer API")

# CORS (Cross-Origin Resource Sharing) 미들웨어 설정
# 프론트엔드(Flutter/Web)가 다른 도메인에서 API를 호출할 수 있도록 허용합니다.

origins_env = os.getenv("ALLOWED_ORIGINS", "*")
origins = [origin.strip() for origin in origins_env.split(",")]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,  # 환경 변수 기반 설정
    allow_credentials=True,
    allow_methods=["*"],  # 모든 HTTP 메서드 허용 (GET, POST 등)
    allow_headers=["*"],  # 모든 헤더 허용
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
app.include_router(websocket_router)
app.include_router(battle_router)

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