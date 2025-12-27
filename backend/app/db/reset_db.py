import asyncio
import sys
import os

# 프로젝트 루트 디렉토리를 path에 추가하여 임포트 허용
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from app.db.database import engine, Base, AsyncSessionLocal
from app.db.models import user, character  # 모든 모델 로드
from app.db.models.user import User
from app.db.models.character import Character, Stat
from app.core.security import get_password_hash

async def reset_database():
    print("--- 데이터베이스 초기화 및 리셋 시작 ---")
    async with engine.begin() as conn:
        print("1. 기존 모든 테이블 삭제 중...")
        await conn.run_sync(Base.metadata.drop_all)
        print("2. 최신 스키마로 테이블 생성 중...")
        await conn.run_sync(Base.metadata.create_all)
        
    print("3. 테스트 데이터 시딩(Seeding) 중...")
    async with AsyncSessionLocal() as session:
        # 테스트용 해시 비밀번호 생성 (보안 반영)
        test_password = get_password_hash("password123")

        # --- User 데이터 (network 브랜치 필드 반영) ---
        # email 대신 username과 nickname을 사용하며 is_active 필드를 추가합니다.
        user1 = User(
            id=1, 
            username="trainer_ash", 
            nickname="지우", 
            password=test_password,
            is_active=True
        )
        user2 = User(
            id=2, 
            username="trainer_gary", 
            nickname="바람", 
            password=test_password,
            is_active=True
        )
        session.add_all([user1, user2])
        await session.flush() # ID 확보를 위한 플러시

        # --- Character 데이터 ---
        # learned_skills는 JSONB 형식으로 저장됩니다.
        char1 = Character(
            user_id=1, 
            name="피카독", 
            pet_type="dog", 
            status="normal",
            learned_skills=[1, 2, 3, 4]
        )
        char2 = Character(
            user_id=2, 
            name="나옹냥", 
            pet_type="cat", 
            status="normal",
            learned_skills=[101, 102, 103, 104]
        )
        session.add_all([char1, char2])
        await session.flush() 

        # --- Stat 데이터 (모델 필드 정밀 동기화) ---
        # Stat 모델에는 max_health 필드가 없으므로 제외합니다.
        # agility, personality, condition 등 develop 모델의 필드를 모두 포함합니다.
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
            personality="기본",
            condition=100,
            unused_points=5
        )
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
            personality="기본",
            condition=100,
            unused_points=5
        )
        session.add_all([stat1, stat2])
        
        await session.commit()
        print("--- 데이터베이스 리셋 및 시딩 완료! ---")

if __name__ == "__main__":
    asyncio.run(reset_database())