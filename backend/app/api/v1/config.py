from fastapi import APIRouter
from app.core.pet_behavior_config import PET_BEHAVIORS, DETECTION_SETTINGS, DEFAULT_BEHAVIOR

router = APIRouter()

@router.get("/game_logic")
async def get_game_logic_config():
    """
    Returns the shared game logic configuration.
    Start-up sync for Edge AI mode.
    """
    return {
        "pet_behaviors": PET_BEHAVIORS,
        "detection_settings": DETECTION_SETTINGS,
        "default_behavior": DEFAULT_BEHAVIOR
    }
