import asyncio
import sys
import os

# Set up path to import app
sys.path.append(os.getcwd())

from app.db.database import AsyncSessionLocal
from app.db.models import user, character, friendship, guestbook, diary, notice
from app.db.models.user import User
from sqlalchemy import select, update

async def fix_admin():
    username = 'rkdgnlwns'
    async with AsyncSessionLocal() as session:
        stmt = select(User).where(User.username == username)
        result = await session.execute(stmt)
        user = result.scalar_one_or_none()
        
        if not user:
            print(f"User {username} not found in database.")
            return

        if not user.is_admin:
            print(f"User {username} found but is NOT admin. Granting admin privileges...")
            await session.execute(update(User).where(User.id == user.id).values(is_admin=True))
            await session.commit()
            print("Successfully granted admin privileges!")
        else:
            print(f"User {username} is already an admin. Login should work.")

if __name__ == "__main__":
    asyncio.run(fix_admin())
