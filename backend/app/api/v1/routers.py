# backend/app/api/v1/routers.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import get_db
from app.services import char_service
from pydantic import BaseModel
from app.api.v1 import chat, auth

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])

user_router = APIRouter(prefix="/users", tags=["users"])
character_router = APIRouter(prefix="/characters", tags=["characters"])

# --- 유저 관련 ---
@user_router.get("/")
async def get_users():
    return [{"message": "사용자 목록 기능 (추후 구현)"}]

# --- 캐릭터 관련 스키마 ---
class CharacterCreate(BaseModel):
    user_id: int
    name: str

class StatUpdateSchema(BaseModel):
    level: int | None = None
    exp: int | None = None
    health: int | None = None
    strength: int | None = None
    intelligence: int | None = None
    stamina: int | None = None
    happiness: int | None = None
    unused_points: int | None = None

# --- 캐릭터 관련 엔드포인트 ---
@character_router.get("/{char_id}")
async def get_character(char_id: int, db: AsyncSession = Depends(get_db)):
    char = await char_service.get_character_with_stats(db, char_id)
    if not char:
        raise HTTPException(status_code=404, detail="Character not found")
    
    return {
        "id": char.id,
        "name": char.name,
        "status": char.status,
        "stats": {
            "level": char.stat.level,
            "exp": char.stat.exp,
            "strength": char.stat.strength,
            "health": char.stat.health,
            "happiness": char.stat.happiness,
            "unused_points": char.stat.unused_points
        }
    }

@character_router.post("/")
async def create_character(char_data: CharacterCreate, db: AsyncSession = Depends(get_db)):
    char = await char_service.create_character(db, char_data.user_id, char_data.name)
    return {"message": "Character created", "id": char.id}

@character_router.put("/{char_id}/stats")
async def update_stats(char_id: int, stat_data: StatUpdateSchema, db: AsyncSession = Depends(get_db)):
    updated_stat = await char_service.update_character_stats(db, char_id, stat_data.dict(exclude_unset=True))
    if not updated_stat:
        raise HTTPException(status_code=404, detail="Character stats not found")
    return {"message": "Stats updated", "stats": updated_stat}

# 라우터 통합
api_router.include_router(user_router)
api_router.include_router(character_router)
api_router.include_router(chat.router, prefix="/chat")