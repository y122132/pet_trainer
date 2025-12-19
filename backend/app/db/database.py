from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase
from typing import AsyncGenerator
import os
from dotenv import load_dotenv

load_dotenv()

# PostgreSQL URL construction from .env
POSTGRES_USER = os.getenv("POSTGRES_USER")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "db")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POSTGRES_DB = os.getenv("POSTGRES_DB")

SQLALCHEMY_DATABASE_URL = f"postgresql+asyncpg://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"

engine = create_async_engine(
    SQLALCHEMY_DATABASE_URL,
    echo=True, # Set to False in production
)

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
    # Import models to ensure they are registered with Base.metadata
    from app.db.models import user, character
    
    async with engine.begin() as conn:
        # await conn.run_sync(Base.metadata.drop_all) # For development reset
        await conn.run_sync(Base.metadata.create_all)
        
    # Seed default user for MVP
    from sqlalchemy import select
    from app.db.models.user import User
    from app.db.models.character import Character, Stat
    
    async with AsyncSessionLocal() as session:
        # 1. Check/Create User
        result = await session.execute(select(User).where(User.id == 1))
        default_user = result.scalar_one_or_none()
        
        if not default_user:
            print("Seeding default user for MVP...")
            default_user = User(id=1, email="test@example.com", password="hashed_password") 
            session.add(default_user)
            await session.commit()
            await session.refresh(default_user)
            
        # 2. Check/Create Character
        char_res = await session.execute(select(Character).where(Character.user_id == 1))
        default_char = char_res.scalar_one_or_none()
        
        if not default_char:
            print("Seeding default character...")
            default_char = Character(user_id=1, name="LifeGotchi", status="normal")
            session.add(default_char)
            await session.commit()
            await session.refresh(default_char)

        # 3. Check/Create Stats
        stat_res = await session.execute(select(Stat).where(Stat.character_id == default_char.id))
        default_stat = stat_res.scalar_one_or_none()
        
        if not default_stat:
            print("Seeding default stats...")
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
            
        print("Default user, character, and stats verification completed.")