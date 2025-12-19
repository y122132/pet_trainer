from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import get_db
from app.services import char_service
from pydantic import BaseModel

api_router = APIRouter(prefix="/v1")

# Create dummy routers for now
user_router = APIRouter(prefix="/users", tags=["users"])
character_router = APIRouter(prefix="/characters", tags=["characters"])

@user_router.get("/")
async def get_users():
    return [{"message": "List of users"}]

# Pydantic Schemas
class CharacterCreate(BaseModel):
    user_id: int
    name: str

@character_router.get("/{char_id}")
async def get_character(char_id: int, db: AsyncSession = Depends(get_db)):
    char = await char_service.get_character_with_stats(db, char_id)
    if not char:
        raise HTTPException(status_code=404, detail="Character not found")
    
    # Manual serialization to simple dict
    return {
        "id": char.id,
        "name": char.name,
        "status": char.status,
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
    char = await char_service.create_character(db, char_data.user_id, char_data.name)
    return {"message": "Character created", "id": char.id}

class StatUpdateSchema(BaseModel):
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
    updated_stat = await char_service.update_character_stats(db, char_id, stat_data.dict(exclude_unset=True))
    if not updated_stat:
        raise HTTPException(status_code=404, detail="Character stats not found")
    return {"message": "Stats updated", "stats": updated_stat}

# Include routers
api_router.include_router(user_router)
api_router.include_router(character_router)
