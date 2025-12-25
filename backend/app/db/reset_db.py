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
        # User 1
        user1 = User(id=1, email="user1@example.com", password="hashed_password")
        session.add(user1)
        
        # User 2
        user2 = User(id=2, email="user2@example.com", password="hashed_password")
        session.add(user2)
        
        await session.flush() # ID 확보

        # Character 1 (Ash) - Dog Level 5 Skills
        char1 = Character(user_id=1, name="지우", pet_type="dog", learned_skills=[1, 2, 3, 4])
        session.add(char1)
        
        # Character 2 (Gary) - Cat Level 5 Skills
        char2 = Character(user_id=2, name="바람", pet_type="cat", learned_skills=[101, 102, 103, 104])
        session.add(char2)
        
        await session.flush()

        # Stat 1
        stat1 = Stat(
            character_id=char1.id,
            health=100,
            happiness=70,
            level=5,
            exp=0,
            strength=15,
            intelligence=10,
            agility=12,
            defense=10,
            luck=10,
            unused_points=5
        )
        session.add(stat1)

        # Stat 2
        stat2 = Stat(
            character_id=char2.id,
            health=100,
            happiness=50,
            level=5,
            exp=50,
            strength=12,
            intelligence=15,
            agility=15,
            defense=8,
            luck=12,
            unused_points=5
        )
        session.add(stat2)
        
        await session.commit()
        print("Database reset and seeded successfully!")

if __name__ == "__main__":
    asyncio.run(reset_database())
