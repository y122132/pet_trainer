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
        # 테스트 유저 생성 함수
        async def create_test_user(uid, email, char_name, pet_type):
            # 1. User
            res = await session.execute(select(User).where(User.id == uid))
            user = res.scalar_one_or_none()
            if not user:
                print(f"Creating Test User {uid}...")
                user = User(id=uid, email=email, password="hashed_password") 
                session.add(user)
                await session.flush()
            
            # 2. Character
            char_res = await session.execute(select(Character).where(Character.user_id == uid))
            char = char_res.scalar_one_or_none()
            if not char:
                print(f"Creating Character for User {uid} ({pet_type})...")
                # 초기 스킬: Dog=[1, 2], Cat=[101, 102]
                skills = [1, 2] if pet_type == 'dog' else [101, 102]
                
                char = Character(
                    user_id=uid, 
                    name=char_name, 
                    status="normal", 
                    pet_type=pet_type,
                    learned_skills=skills
                )
                session.add(char)
                await session.flush()
                
            # 3. Stat
            stat_res = await session.execute(select(Stat).where(Stat.character_id == char.id))
            stat = stat_res.scalar_one_or_none()
            if not stat:
                print(f"Creating Stats for User {uid}...")
                stat = Stat(
                    character_id=char.id,
                    strength=10,
                    intelligence=10,
                    agility=10,
                    happiness=50,
                    health=100,
                    defense=10,    # Default
                    luck=5,        # Default
                    condition=100  # Default
                )
                session.add(stat)
        
        # 유저 1 (강아지)
        await create_test_user(1, "test1@example.com", "MyDog", "dog")
        # 유저 2 (고양이)
        await create_test_user(2, "test2@example.com", "EnemyCat", "cat")
        
        await session.commit()
            
        print("Test environment initialized (Users 1 & 2 created).")