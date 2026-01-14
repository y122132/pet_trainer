import asyncio
import sys
from sqlalchemy import select

# 프로젝트 루트 경로 추가 (모듈 import 문제 해결)
import os
sys.path.append(os.getcwd())

from app.db.database import AsyncSessionLocal
from app.db.models.user import User
# 관계 매핑을 위해 필요한 경우 모델 로드 (여기선 User만 직접 사용하지만, Base registry를 위해 필요할 수 있음)
from app.db.models import diary, character, friendship, guestbook
from app.core.security import get_password_hash

async def create_superuser():
    username = input("Enter Admin Username: ")
    password = input("Enter Admin Password: ")
    nickname = input("Enter Admin Nickname (Optional): ") or "Admin"
    
    async with AsyncSessionLocal() as session:
        # Check existing
        stmt = select(User).where(User.username == username)
        existing = await session.execute(stmt)
        if existing.scalar_one_or_none():
            print(f"User {username} already exists!")
            return

        print("Creating superuser...")
        admin_user = User(
            username=username,
            password=get_password_hash(password),
            nickname=nickname,
            is_active=True,
            is_admin=True # 관리자 권한 부여
        )
        session.add(admin_user)
        await session.commit()
        print(f"Superuser '{username}' created successfully!")

if __name__ == "__main__":
    asyncio.run(create_superuser())
