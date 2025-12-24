from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import get_db
from app.services import char_service
from pydantic import BaseModel

# API 버전 관리를 위한 프리픽스 설정 (/v1)
api_router = APIRouter(prefix="/v1")

# 라우터 그룹 분리 (현재는 간단하게 여기서 정의하지만, 추후 별도 파일로 분리 가능)
user_router = APIRouter(prefix="/users", tags=["users"])
character_router = APIRouter(prefix="/characters", tags=["characters"])

@user_router.get("/")
async def get_users():
    """사용자 목록 조회 (테스트용)"""
    return [{"message": "List of users"}]

# --- Pydantic 스키마 (데이터 검증 모델) ---
class CharacterCreate(BaseModel):
    user_id: int
    name: str

# --- 캐릭터 관련 엔드포인트 ---

@character_router.get("/{char_id}")
async def get_character(char_id: int, db: AsyncSession = Depends(get_db)):
    """
    특정 캐릭터의 상세 정보와 스탯을 조회합니다.
    """
    char = await char_service.get_character_with_stats(db, char_id)
    if not char:
        raise HTTPException(status_code=404, detail="Character not found")
    
    # ORM 객체를 딕셔너리로 수동 직렬화 (간단한 응답 구조)
    # ORM 객체를 딕셔너리로 수동 직렬화 (간단한 응답 구조)
    return {
        "id": char.id,
        "user_id": char.user_id, # [Fix] user_id 추가
        "name": char.name,
        "status": char.status,
        "pet_type": char.pet_type, 
        "learned_skills": char.learned_skills, # [New] 스킬 목록 추가
        "stats": {
            "level": char.stat.level,
            "exp": char.stat.exp,
            "strength": char.stat.strength,
            "intelligence": char.stat.intelligence, 
            "stamina": char.stat.stamina, 
            "happiness": char.stat.happiness,
            "health": char.stat.health,
            "unused_points": char.stat.unused_points
        }
    }

@character_router.post("/")
async def create_character(char_data: CharacterCreate, db: AsyncSession = Depends(get_db)):
    """
    새로운 캐릭터를 생성합니다.
    """
    char = await char_service.create_character(db, char_data.user_id, char_data.name)
    return {"message": "Character created", "id": char.id}

class StatUpdateSchema(BaseModel):
    """스탯 업데이트 요청 데이터 모델"""
    level: int | None = None
    exp: int | None = None
    health: int | None = None
    strength: int | None = None
    intelligence: int | None = None
    stamina: int | None = None
    happiness: int | None = None
    unused_points: int | None = None

@character_router.put("/{char_id}/stats")
async def update_stats(char_id: int, stat_data: StatUpdateSchema, db: AsyncSession = Depends(get_db)):
    """
    캐릭터의 스탯 정보를 수정합니다. (클라이언트 동기화용)
    """
    updated_stat = await char_service.update_character_stats(db, char_id, stat_data.dict(exclude_unset=True))
    if not updated_stat:
        raise HTTPException(status_code=404, detail="Character stats not found")
    return {"message": "Stats updated", "stats": updated_stat}

# 라우터들을 메인 API 라우터에 통합
api_router.include_router(user_router)
api_router.include_router(character_router)
