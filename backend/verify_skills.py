import asyncio
import os
# Override DB host for local verification
os.environ["POSTGRES_HOST"] = "localhost"

from app.db.database import AsyncSessionLocal
from app.db.models.user import User
from app.db.models.character import Character, Stat
from app.db.models.diary import Diary # Import to resolve relationship
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from app.services import char_service
import json

async def verify():
    async with AsyncSessionLocal() as db:
        # 1. Find a character with stats eagerly loaded
        stmt = select(Character).options(selectinload(Character.stat)).limit(1)
        result = await db.execute(stmt)
        char = result.scalar_one_or_none()
        
        if not char:
            print("No character found to test.")
            return

        print(f"--- START VERIFICATION ---")
        print(f"Character ID: {char.id}, Name: {char.name}")
        print(f"Level: {char.stat.level}, Exp: {char.stat.exp}")
        print(f"Learned Skills: {char.learned_skills}")

        # 2. Level up to 80 to test skills 301, 302, 303
        target_level = 80
        if char.stat.level < target_level:
            print(f"Leveling up to {target_level}...")
            # Calculate needed exp
            while char.stat.level < target_level:
                exp_needed = char.stat.level * 100 - char.stat.exp + 10
                await char_service._give_exp_and_levelup(db, char, exp_needed)
                await db.refresh(char)
            
            print(f"Target level reached: {char.stat.level}")
            print(f"Learned Skills now: {char.learned_skills}")
        else:
            print(f"Already at level {char.stat.level}. Re-running level up logic to ensure skills are learned.")
            await char_service._give_exp_and_levelup(db, char, 10)
            await db.refresh(char)
            print(f"Learned Skills now: {char.learned_skills}")

        results = {
            301: 301 in char.learned_skills,
            302: 302 in char.learned_skills,
            303: 303 in char.learned_skills
        }
        
        for sid, success in results.items():
            if success:
                print(f"SUCCESS: Skill {sid} learned!")
            else:
                print(f"FAILURE: Skill {sid} NOT found.")
            
        print(f"--- END VERIFICATION ---")

if __name__ == "__main__":
    asyncio.run(verify())
