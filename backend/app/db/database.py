from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase
from typing import AsyncGenerator
import os
from dotenv import load_dotenv

load_dotenv()

# .env 파일에서 데이터베이스 연결 정보 로드
POSTGRES_USER = os.getenv("POSTGRES_USER")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "db")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POSTGRES_DB = os.getenv("POSTGRES_DB")

# PostgreSQL 비동기 연결 URL (asyncpg 드라이버 사용)
SQLALCHEMY_DATABASE_URL = f"postgresql+asyncpg://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"

# 비동기 엔진 생성
engine = create_async_engine(
    SQLALCHEMY_DATABASE_URL,
    echo=True, # 쿼리 로그 출력 (운영 환경에서는 False로 설정 권장)
)

# 비동기 세션 팩토리 생성
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False, # 커밋 후 객체 만료 방지 (비동기 환경에서 재조회 방지)
    autoflush=False,
)

class Base(DeclarativeBase):
    pass

# FastAPI 의존성 주입(Dependency Injection)을 위한 DB 세션 생성기
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session

# 데이터베이스 초기화 함수 (Startup 시 실행)
async def init_db():
    # Base.metadata에 모델을 등록하기 위해 모델들을 import 해야 함
    from app.db.models import user, character
    
    # 테이블 생성 (이미 존재하면 건너뜀)
    async with engine.begin() as conn:
        # await conn.run_sync(Base.metadata.drop_all) # 개발 중 초기화가 필요할 때 사용 (주의!)
        await conn.run_sync(Base.metadata.create_all)
        
    # MVP 테스트를 위한 기본(Default) 데이터 시딩
    from sqlalchemy import select
    from app.db.models.user import User
    from app.db.models.character import Character, Stat
    
    async with AsyncSessionLocal() as session:
        # 1. 기본 사용자 확인 및 생성
        result = await session.execute(select(User).where(User.id == 1))
        default_user = result.scalar_one_or_none()
        
        if not default_user:
            print("Seeding default user for MVP... (기본 사용자 생성)")
            default_user = User(id=1, email="test@example.com", password="hashed_password") 
            session.add(default_user)
            await session.commit()
            await session.refresh(default_user)
            
        # 2. 기본 캐릭터 확인 및 생성
        char_res = await session.execute(select(Character).where(Character.user_id == 1))
        default_char = char_res.scalar_one_or_none()
        
        if not default_char:
            print("Seeding default character... (기본 캐릭터 생성)")
            default_char = Character(user_id=1, name="PetTrainer", status="normal")
            session.add(default_char)
            await session.commit()
            await session.refresh(default_char)

        # 3. 기본 스탯 생성
        stat_res = await session.execute(select(Stat).where(Stat.character_id == default_char.id))
        default_stat = stat_res.scalar_one_or_none()
        
        if not default_stat:
            print("Seeding default stats... (기본 스탯 생성)")
            new_stat = Stat(
                character_id=default_char.id,
                strength=10,
                intelligence=10,
                stamina=10,
                happiness=50,
                health=100
            )
            session.add(new_stat)
            await session.commit()
            
        print("Default user, character, and stats verification completed. (데이터 초기화 완료)")