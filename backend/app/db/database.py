# backend/app/db/database.py
import os
from dotenv import load_dotenv
from typing import AsyncGenerator
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

load_dotenv()

# 데이터베이스 연결 정보 설정
POSTGRES_USER = os.getenv("POSTGRES_USER")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "db")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POSTGRES_DB = os.getenv("POSTGRES_DB")

SQLALCHEMY_DATABASE_URL = f"postgresql+asyncpg://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"

engine = create_async_engine(SQLALCHEMY_DATABASE_URL, echo=True)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)

class Base(DeclarativeBase):
    pass

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session

async def init_db():
    """
    서버 시작 시 테이블을 생성하고 최신화된 모델 필드에 맞춰 테스트 데이터를 시딩합니다.
    """
    # Base.metadata 등록을 위해 모델 임포트
    from app.db.models import user, character, friendship, diary, chat_data, guestbook
    
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        

    
    print("--- [DB] 모든 테이블 구조 생성 및 확인 완료 ---")