import asyncio
import sys
import os

# Add parent directory to path to allow imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from app.db.database import engine, Base, AsyncSessionLocal
from app.db.models import user, character # Import ALL models
from sqlalchemy import select
from app.db.models.user import User
from app.db.models.character import Character, Stat

async def reset_database():
    print("resetting database...")
    async with engine.begin() as conn:
        print("Dropping all tables...")
        await conn.run_sync(Base.metadata.drop_all)
        print("Creating all tables...")
        await conn.run_sync(Base.metadata.create_all)
        
    print("Seeding default data...")
    async with AsyncSessionLocal() as session:
        # User
        new_user = User(id=1, email="test@example.com", password="hashed_password")
        session.add(new_user)
        await session.commit()
        
        # Character
        new_char = Character(user_id=1, name="LifeGotchi")
        session.add(new_char)
        await session.commit()
        
        # Stat (Initial values)
        new_stat = Stat(
            character_id=new_char.id,
            health=100,
            happiness=100,
            level=1,
            exp=0,
            strength=10,
            intelligence=10,
            stamina=10,
            unused_points=0
        )
        session.add(new_stat)
        await session.commit()
        print("Database reset and seeded successfully!")

if __name__ == "__main__":
    asyncio.run(reset_database())
