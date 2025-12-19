import asyncio
import os
import sys

# Add backend directory to path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.db.database import engine, Base, AsyncSessionLocal
from app.db.models import user, character
from app.db.models.user import User
from app.db.models.character import Character, Stat
from sqlalchemy import select

async def reset_database():
    print("🗑️  Dropping all tables...")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    print("✅  Tables re-created.")

    print("🌱  Seeding data...")
    async with AsyncSessionLocal() as session:
        # 1. Create User
        print("   - Creating User 1...")
        new_user = User(id=1, email="test@example.com", hashed_password="hashed_password") 
        session.add(new_user)
        
        # 2. Create Character
        print("   - Creating Character 'LifeGotchi'...")
        new_char = Character(user_id=1, name="LifeGotchi", status="normal")
        session.add(new_char)
        await session.flush() # Ensure ID is generated

        # 3. Create Stats
        print("   - Creating Initial Stats...")
        new_stat = Stat(
            character_id=new_char.id,
            strength=10,
            intelligence=10,
            stamina=10,
            happiness=50,
            health=100,
            level=1,
            exp=0,
            unused_points=0
        )
        session.add(new_stat)
        
        await session.commit()
        print("🎉  Seeding Complete! (User ID: 1, Character ID: 1)")

if __name__ == "__main__":
    try:
        asyncio.run(reset_database())
    except Exception as e:
        print(f"❌  Error during reset: {e}")
