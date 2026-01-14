import asyncio
import sys
import os

sys.path.append(os.path.join(os.getcwd(), 'backend'))

from app.db.database import get_db
from app.db.models.character import Character
from sqlalchemy import select

async def check_db():
    async for db in get_db():
        stmt = select(Character)
        res = await db.execute(stmt)
        chars = res.scalars().all()
        print(f"Total Characters: {len(chars)}")
        for c in chars:
            print(f"ID: {c.id}, UserID: {c.user_id}, Name: {c.name}, Type: {c.pet_type}, Skills: {c.learned_skills}")
        break

if __name__ == "__main__":
    asyncio.run(check_db())
