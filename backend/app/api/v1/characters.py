# backend/app/api/v1/characters.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import get_db
from app.services import char_service
from pydantic import BaseModel

# 캐릭터 전용 라우터 정의
router = APIRouter(prefix="/characters", tags=["characters"])

# --- Pydantic 스키마 (데이터 검증 모델) ---
class CharacterCreate(BaseModel):
    user_id: int
    name: str

class StatUpdateSchema(BaseModel):
    """스탯 업데이트 요청 데이터 모델"""
    level: int | None = None
    exp: int | None = None
    health: int | None = None
    strength: int | None = None
    intelligence: int | None = None
    agility: int | None = None
    defense: int | None = None
    luck: int | None = None
    happiness: int | None = None
    unused_points: int | None = None

# --- 캐릭터 관련 엔드포인트 ---

@router.get("/{char_id}")
async def get_character(char_id: int, db: AsyncSession = Depends(get_db)):
    """특정 캐릭터의 상세 정보와 스탯을 조회합니다."""
    char = await char_service.get_character_with_stats(db, char_id)
    if not char:
        raise HTTPException(status_code=404, detail="Character not found")
    
    return {
        "id": char.id,
        "user_id": char.user_id,
        "name": char.name,
        "status": char.status,
        "pet_type": char.pet_type, 
        "learned_skills": char.learned_skills,
        "stats": {
            "level": char.stat.level,
            "exp": char.stat.exp,
            "strength": char.stat.strength,
            "intelligence": char.stat.intelligence, 
            "agility": char.stat.agility, 
            "defense": char.stat.defense,
            "luck": char.stat.luck,
            "happiness": char.stat.happiness,
            "health": char.stat.health,
            "unused_points": char.stat.unused_points
        }
    }

@router.post("/")
async def create_character(char_data: CharacterCreate, db: AsyncSession = Depends(get_db)):
    """새로운 캐릭터를 생성합니다."""
    try:
        char = await char_service.create_character(db, char_data.user_id, char_data.name)
        return {"message": "Character created", "id": char.id}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

@router.put("/{char_id}/stats")
async def update_stats(char_id: int, stat_data: StatUpdateSchema, db: AsyncSession = Depends(get_db)):
    """캐릭터의 스탯 정보를 수정합니다."""
    updated_stat = await char_service.update_character_stats(db, char_id, stat_data.dict(exclude_unset=True))
    if not updated_stat:
        raise HTTPException(status_code=404, detail="Character stats not found")
    return {"message": "Stats updated", "stats": updated_stat}