from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.v1.routers import api_router
from app.sockets.analysis_socket import router as websocket_router
from app.db.database import init_db
from app.ai_core.vision import detector

app = FastAPI(title="PetTrainer API")

# CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Startup event for DB initialization
@app.on_event("startup")
async def on_startup():
    await init_db()
    # Preload YOLO models
    detector.load_models()

# Include Routers
app.include_router(api_router)
app.include_router(websocket_router)

@app.get("/")
async def root():
    return {"message": "Welcome to PetTrainer API"}