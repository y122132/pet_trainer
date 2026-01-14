import asyncio
import sys
import os

# Add backend to path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from app.db.database import get_db, engine, Base
from app.services import char_service
from app.db.models.character import Character, Stat
from sqlalchemy import select

async def test_creation(pet_type, name):
    print(f"\n--- Testing Creation for {pet_type} ({name}) ---")
    async for db in get_db():
        # Using user_id 1 for test (adjust if needed or use a dummy)
        try:
            # Clean up existing test char if any
            stmt = select(Character).where(Character.user_id == 999)
            res = await db.execute(stmt)
            existing = res.scalar_one_or_none()
            if existing:
                await char_service.delete_character(db, existing.id)
                print("Cleaned up existing test character.")

            char = await char_service.create_character(db, user_id=999, name=name, pet_type=pet_type)
            print(f"Created Character: {char.name}, Type: {char.pet_type}")
            print(f"Learned Skills: {char.learned_skills}")
            print(f"Equipped Skills: {char.equipped_skills}")
            
            # Verify skills
            from app.game.game_assets import PET_LEARNSET
            expected = PET_LEARNSET.get(pet_type, {}).get(5, [5])
            if char.learned_skills == expected:
                print("✅ Skill verification SUCCESS")
            else:
                print(f"❌ Skill verification FAILED. Expected {expected}, got {char.learned_skills}")
                
            # Clean up
            await char_service.delete_character(db, char.id)
            print("Cleanup done.")
            
        except Exception as e:
            print(f"Error: {e}")
        break

async def main():
    await test_creation("dog", "TestDog")
    await test_creation("cat", "TestCat")
    await test_creation("bird", "TestBird")

if __name__ == "__main__":
    asyncio.run(main())
