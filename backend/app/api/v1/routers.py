# backend/app/api/v1/routers.py
from fastapi import APIRouter
from app.api.v1 import chat, auth, characters 
from app.api.v1 import battle

api_router = APIRouter(prefix="/v1")
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(chat.router, prefix="/chat", tags=["chat"])
api_router.include_router(characters.router)
api_router.include_router(battle.router, prefix="/battle", tags=["battle"])