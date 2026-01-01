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

# --- Interaction Endpoint ---
from app.services.weather_service import get_weather_info
from app.ai_core.brain.graphs import get_character_response
from datetime import datetime
import pytz

class InteractionRequest(BaseModel):
    action_type: str # touch, stroke, poke, idle ...
    lat: float | None = None
    lon: float | None = None
    client_timestamp: float | None = None

@router.post("/{char_id}/interaction")
async def interact_with_character(char_id: int, req: InteractionRequest, db: AsyncSession = Depends(get_db)):
    """
    캐릭터와의 비언어적 상호작용(터치 등)을 처리하고 반응(대사)을 반환합니다.
    - 날씨, 시간, 장기 기억이 반영된 대사가 생성됩니다.
    """
    # 1. 캐릭터 존재 확인
    char = await char_service.get_character_with_stats(db, char_id)
    if not char:
        raise HTTPException(status_code=404, detail="Character not found")
        
    # 2. 날씨 조회 (좌표 있을 경우)
    weather_info = {}
    if req.lat is not None and req.lon is not None:
        weather_info = await get_weather_info(req.lat, req.lon)
        
    # 3. 시간 변환
    client_time_str = ""
    if req.client_timestamp:
        try:
            # 타임스탬프 -> KST 변환 (혹은 클라이언트 로컬 타임 유추)
            # 여기서는 편의상 Server Time(Korean Standard Time presumed) or simple conversion
            dt = datetime.fromtimestamp(req.client_timestamp)
            client_time_str = dt.strftime("%Y-%m-%d %H:%M")
        except:
            client_time_str = datetime.now().strftime("%Y-%m-%d %H:%M")
    else:
        client_time_str = datetime.now().strftime("%Y-%m-%d %H:%M")

    # 4. Brain(LLM) 실행
    response_text = await get_character_response(
        user_id=char.user_id,
        action_type=req.action_type,
        current_stats={
            "strength": char.stat.strength,
            "happiness": char.stat.happiness,
            # 필요한 스탯 추가
        },
        mode="interaction", # 마이룸 상호작용 모드
        weather_info=weather_info,
        client_time=client_time_str
    )
    
    return {
        "character_id": char_id,
        "action": req.action_type,
        "response": response_text,
        "weather_summary": weather_info.get("desc", "unknown")
    }