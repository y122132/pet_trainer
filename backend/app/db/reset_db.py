import asyncio
import sys
import os

# 프로젝트 루트 디렉토리를 path에 추가
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from app.db.database import engine, Base
from app.db.models import user, character, guestbook, friendship, diary, chat_data  # 모든 모델 로드

async def reset_database():
    print("--- [주의] 데이터베이스 스키마 초기화 시작 ---")
    
    async with engine.begin() as conn:
        print("1. 기존 테이블 및 데이터 전체 삭제 중...")
        # 기존의 모든 테이블을 삭제합니다. (테스트 데이터 포함 모든 데이터가 날아갑니다)
        await conn.run_sync(Base.metadata.drop_all)
        
        print("2. 최신 스킬 시스템 필드가 반영된 새 테이블 생성 중...")
        # Character 모델의 learned_skills, equipped_skills 필드 등이 포함된 새 테이블 생성
        await conn.run_sync(Base.metadata.create_all)
        
    print("--- [완료] DB가 깨끗하게 리셋되었습니다. 이제 실제 데이터를 등록하세요! ---")

if __name__ == "__main__":
    # 비동기 실행
    asyncio.run(reset_database())