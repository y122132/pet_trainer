from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase
from typing import AsyncGenerator
import os
from dotenv import load_dotenv

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
    from app.db.models import user, character, friendship
    
    async with engine.begin() as conn:
        # 테이블 생성
        await conn.run_sync(Base.metadata.create_all)
        
    from sqlalchemy import select
    from app.db.models.user import User
    from app.db.models.character import Character, Stat
    from app.core.security import get_password_hash

    async with AsyncSessionLocal() as session:
        test_hashed_pwd = get_password_hash("password123")

        async def create_test_user(username, nickname, char_name, pet_type):
            # 1. User 필드 체크: username, nickname, password, is_active (email은 nullable이므로 생략 가능)
            res = await session.execute(select(User).where(User.username == username))
            user_obj = res.scalar_one_or_none()
            if not user_obj:
                print(f"Creating Test User {username}...")
                user_obj = User(
                    # id=uid, 
                    username=username, 
                    nickname=nickname, 
                    password=test_hashed_pwd,
                    is_active=True # User 모델에 추가된 필드 확인됨
                ) 
                session.add(user_obj)
                await session.flush()
            
            # 2. Character 필드 체크: name, status, pet_type, learned_skills (JSONB)
            char_res = await session.execute(select(Character).where(Character.user_id == user_obj.id))
            char = char_res.scalar_one_or_none()
            if not char:
                print(f"Creating Character for User {username}...")
                skills = [1, 2] if pet_type == 'dog' else [101, 102]
                char = Character(
                    user_id=user_obj.id, 
                    name=char_name, 
                    status="normal", 
                    pet_type=pet_type,
                    learned_skills=skills # develop 브랜치 필수 필드
                )
                session.add(char)
                await session.flush()
                
            # 3. Stat 필드 체크: agility(O), max_health(X), personality/condition(O)
            stat_res = await session.execute(select(Stat).where(Stat.character_id == char.id))
            stat = stat_res.scalar_one_or_none()
            if not stat:
                print(f"Creating Stats for User {username}...")
                # character.py 모델 정의에 맞춰 정확히 매칭 (max_health 제거)
                stat = Stat(
                    character_id=char.id,
                    level=5,
                    exp=0,
                    health=100,      # 모델의 health 필드 사용
                    happiness=70,
                    strength=15,
                    intelligence=10,
                    agility=12,      # develop의 agility 사수
                    defense=10,
                    luck=10,
                    personality="기본", # develop 모델 필드
                    condition=100,   # develop 모델 필드
                    unused_points=5
                )
                session.add(stat)
        
        # 테스트 데이터 생성 실행
        await create_test_user("trainer_ash", "지우", "피카독", "dog")
        await create_test_user("trainer_gary", "바람", "나옹냥", "cat")
        
        await session.commit()
        print("--- 테스트 환경 초기화 완료 (User/Character/Stat 연동 완료) ---")