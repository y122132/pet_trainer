# backend/app/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.v1.routers import api_router
from app.sockets.analysis_socket import router as websocket_router
from app.db.database import init_db
from app.ai_core.vision import detector
from app.api.v1.chat import router as chat_router

app = FastAPI(title="PetTrainer API")

# CORS (Cross-Origin Resource Sharing) 미들웨어 설정
# 프론트엔드(Flutter/Web)가 다른 도메인에서 API를 호출할 수 있도록 허용합니다.
# 보안상 실제 운영 환경에서는 allow_origins를 특정 도메인으로 제한하는 것이 좋습니다.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 모든 출처(Origin) 허용 (개발용)
    allow_credentials=True,
    allow_methods=["*"],  # 모든 HTTP 메서드 허용 (GET, POST 등)
    allow_headers=["*"],  # 모든 헤더 허용
)

@app.on_event("startup")
async def on_startup():
    detector.load_models()
    print("--- 서버 초기화 완료! 이제 요청을 받을 수 있습니다 ---")
app.include_router(api_router, prefix="/api/v1")
app.include_router(chat_router, prefix="/chat", tags=["chat"])

@app.get("/")
async def root():
    return {"message": "Welcome to PetTrainer API"}