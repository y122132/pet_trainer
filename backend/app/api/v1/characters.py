# backend/app/api/v1/characters.py
import os
import time
import shutil
from pathlib import Path
from sqlalchemy import select
from pydantic import BaseModel
from app.db.database import get_db
from sqlalchemy.orm import Session
from app.db.models.user import User
from app.services import char_service
from app.db.models.character import Character
from sqlalchemy.ext.asyncio import AsyncSession
from app.schemas.character import EquipSkillsRequest
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form

from app.core.security import get_current_user_id
# 캐릭터 전용 라우터 정의
router = APIRouter(prefix="/characters", tags=["characters"])

# 업로드 디렉토리 설정
UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

# 허용된 이미지 확장자
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp'}

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
    char = await char_service.get_character(db, char_id)
    if not char:
        raise HTTPException(status_code=404, detail="Character not found")
    
    return {
        "id": char.id,
        "user_id": char.user_id,
        "name": char.name,
        "status": char.status,
        "pet_type": char.pet_type, 
        "learned_skills": char.learned_skills,
        "equipped_skills": char.equipped_skills,
        "front_url": char.front_url,
        "back_url": char.back_url,
        "side_url": char.side_url,
        "face_url": char.face_url,
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
async def update_stats(
    char_id: int, 
    stat_data: StatUpdateSchema, 
    db: AsyncSession = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    """캐릭터의 스탯 정보를 수정합니다."""
    # 1. 캐릭터 존재 및 소유권 확인
    char = await char_service.get_character(db, char_id)
    if not char:
        raise HTTPException(status_code=404, detail="Character not found")
    
    if char.user_id != current_user_id:
        raise HTTPException(status_code=403, detail="Not authorized to update this character")

    # 2. 스탯 업데이트 실행
    updated_stat = await char_service.update_character_stats(db, char_id, stat_data.dict(exclude_unset=True))
    if not updated_stat:
        raise HTTPException(status_code=404, detail="Character stats not found")
    return {"message": "Stats updated", "stats": updated_stat}

@router.post("/{char_id}/level-up")
async def manual_level_up(char_id: int, db: AsyncSession = Depends(get_db)):
    char = await char_service.get_character(db, char_id)
    if not char:
        raise HTTPException(status_code=404, detail="Character not found")
    
    await db.refresh(char)
    
    exp_needed = char.stat.level * 100
    result = await char_service._give_exp_and_levelup(db, char, exp_needed)
    
    await db.flush()
    # await char_service.check_and_unlock_skills(db, char, char.stat.level) # _give_exp_and_levelup now handles this
    
    await db.commit()
    await db.refresh(char)
    return {
        "id": char.id,
        "user_id": char.user_id,
        "name": char.name,
        "pet_type": char.pet_type,
        "learned_skills": char.learned_skills,
        "equipped_skills": char.equipped_skills,
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
        },
        "level_up_result": result # Return full result for debugging/frontend usage
    }

@router.post("/compose")
async def create_character_with_images(
    name: str = Form(...),
    pet_type: str = Form("dog"),
    front_image: UploadFile = File(..., alias="front_image"),
    back_image: UploadFile = File(..., alias="back_image"),
    side_image: UploadFile = File(..., alias="side_image"),
    face_image: UploadFile = File(..., alias="face_image"),
    db: AsyncSession = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    print(f"--- [DEBUG] API /compose called: name={name}, pet_type={pet_type}, user_id={current_user_id} ---")
    # 1. 파일 확장자 선검사 (빠른 실패)
    image_files = [front_image, back_image, side_image, face_image]
    for file in image_files:
        if not file.filename:
             raise HTTPException(status_code=400, detail="Filename cannot be empty")
        
        ext = Path(file.filename).suffix.lower()
        if not ext or ext.replace('.', '') not in ALLOWED_EXTENSIONS:
            raise HTTPException(status_code=400, detail=f"File type not allowed: {ext}")

    # 2. 캐릭터 생성 (DB)
    try:
        char = await char_service.create_character(db, current_user_id, name, pet_type)
    except ValueError as e:
        status_code = 400
        if "User not found" in str(e): # User check fail
             status_code = 404
        raise HTTPException(status_code=status_code, detail=str(e))

    # 3. 이미지 저장
    image_file_map = {
        "front_url": front_image,
        "back_url": back_image,
        "side_url": side_image,
        "face_url": face_image,
    }
    image_urls = {}
    
    try:
        for key, file in image_file_map.items():
            timestamp = int(time.time())
            ext = Path(file.filename).suffix
            new_filename = f"user{current_user_id}_{key}_{timestamp}{ext}"
            
            file_location = os.path.join(UPLOAD_DIR, new_filename)
            
            with open(file_location, "wb+") as file_object:
                shutil.copyfileobj(file.file, file_object)
                
            image_urls[key] = f"/{UPLOAD_DIR}/{new_filename}"
            
        # 4. URL 업데이트
        updated_char = await char_service.update_character_image_urls(db, char.id, image_urls)
        
        return {"success": True, "message": "Character created successfully", "id": char.id, "character": updated_char}

    except Exception as e:
        # **롤백 실행**: 이미지가 하나라도 실패하면 캐릭터 삭제
        print(f"[Create Error] Rolling back character {char.id}: {e}")
        await char_service.delete_character(db, char.id)
        raise HTTPException(status_code=500, detail=f"Image upload failed. Character creation rolled back. Error: {str(e)}")


@router.put("/{char_id}/images")
async def update_character_images(
    char_id: int, 
    db: AsyncSession = Depends(get_db),
    front_image: UploadFile = File(..., alias="front_image"),
    back_image: UploadFile = File(..., alias="back_image"),
    side_image: UploadFile = File(..., alias="side_image"),
    face_image: UploadFile = File(..., alias="face_image"),
    current_user_id: int = Depends(get_current_user_id)
):
    """캐릭터의 이미지 파일들을 업로드하고 URL을 업데이트합니다."""
    
    # 1. 캐릭터 소유권 확인
    char = await char_service.get_character(db, char_id)
    if not char:
        raise HTTPException(status_code=404, detail="Character not found")
    
    if char.user_id != current_user_id:
        raise HTTPException(status_code=403, detail="Not authorized to update this character")

    image_files = {
        "front_url": front_image,
        "back_url": back_image,
        "side_url": side_image,
        "face_url": face_image,
    }
    
    image_urls = {}

    for key, file in image_files.items():
        # 2. 파일 확장자 검사
        if not file.filename:
             raise HTTPException(status_code=400, detail="Filename cannot be empty")
        
        ext = Path(file.filename).suffix.lower()
        if not ext or ext.replace('.', '') not in ALLOWED_EXTENSIONS:
            raise HTTPException(status_code=400, detail=f"File type not allowed: {ext}. Allowed: {ALLOWED_EXTENSIONS}")

        # [Bonus] 기존 파일 삭제 (청소)
        old_url = getattr(char, key)
        if old_url:
            old_path = old_url.lstrip('/')
            if os.path.exists(old_path):
                try:
                    os.remove(old_path)
                    print(f"Deleted old file: {old_path}")
                except Exception as e:
                    print(f"Failed to delete old file {old_path}: {e}")

        # 파일 저장 경로 및 URL 생성
        timestamp = int(time.time())
        new_filename = f"user{current_user_id}_{key}_{timestamp}{ext}"
        file_location = os.path.join(UPLOAD_DIR, new_filename)
        
        with open(file_location, "wb+") as file_object:
            shutil.copyfileobj(file.file, file_object)
            
        image_urls[key] = f"/{UPLOAD_DIR}/{new_filename}"

    # 서비스 계층을 호출하여 데이터베이스의 URL 업데이트
    updated_character = await char_service.update_character_image_urls(db, char_id, image_urls)
    
    if not updated_character:
        raise HTTPException(status_code=404, detail="Character not found")
        
    return {"message": "Image files uploaded and URLs updated successfully", "image_urls": image_urls}

@router.put("/{char_id}/image/{image_key}")
async def update_single_character_image(
    char_id: int,
    image_key: str,
    image_file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    """단일 캐릭터 이미지를 업데이트합니다."""
    # 1. 캐릭터 소유권 확인
    char = await char_service.get_character(db, char_id)
    if not char:
        raise HTTPException(status_code=404, detail="Character not found")
    
    if char.user_id != current_user_id:
        raise HTTPException(status_code=403, detail="Not authorized to update this character")

    # 2. 유효한 image_key 인지 확인
    if image_key not in ["front_url", "back_url", "side_url", "face_url"]:
        raise HTTPException(status_code=400, detail="Invalid image key provided.")

    # 3. 파일 확장자 검사
    if not image_file.filename:
        raise HTTPException(status_code=400, detail="Filename cannot be empty")
    
    ext = Path(image_file.filename).suffix.lower()
    if not ext or ext.replace('.', '') not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail=f"File type not allowed: {ext}")

    # 4. 기존 파일 삭제
    old_url = getattr(char, image_key, None)
    if old_url:
        old_path = old_url.lstrip('/')
        if os.path.exists(old_path):
            try:
                os.remove(old_path)
                print(f"Deleted old file: {old_path}")
            except Exception as e:
                print(f"Failed to delete old file {old_path}: {e}")

    # 5. 새 파일 저장 및 URL 생성
    timestamp = int(time.time())
    new_filename = f"user{current_user_id}_{image_key}_{timestamp}{ext}"
    file_location = os.path.join(UPLOAD_DIR, new_filename)
    
    with open(file_location, "wb+") as file_object:
        shutil.copyfileobj(image_file.file, file_object)
        
    new_image_url = f"/{UPLOAD_DIR}/{new_filename}"

    # 6. DB 업데이트
    updated_character = await char_service.update_character_image_urls(db, char_id, {image_key: new_image_url})
    
    if not updated_character:
        raise HTTPException(status_code=404, detail="Character not found after update attempt")
        
    return {"message": f"{image_key} updated successfully", "image_url": new_image_url}

@router.post("/me/equip-skills")
async def equip_skills(
    req: EquipSkillsRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    print(f"[DEBUG] 스킬 장착 시도 - 유저 ID: {current_user_id}")
    char_res = await db.execute(select(Character).where(Character.user_id == current_user_id))
    char = char_res.scalar_one_or_none()
    if not char:
        print(f"[ERROR] 유저 {current_user_id}에게 할당된 캐릭터가 DB에 없습니다.")
        raise HTTPException(status_code=404, detail="캐릭터를 찾을 수 없습니다.")

    # 1. 검증: 최대 4개 제한
    if len(req.skill_ids) > 4:
        raise HTTPException(status_code=400, detail="최대 4개까지 장착 가능합니다.")

    # 2. 검증: 실제로 해금(learned)한 스킬인가?
    for s_id in req.skill_ids:
        if s_id not in char.learned_skills:
            raise HTTPException(status_code=403, detail=f"미해금 스킬 포함: {s_id}")

    # 3. 저장
    char.equipped_skills = req.skill_ids
    db.add(char) 
    await db.commit()
    
    return {"status": "success", "equipped_skills": char.equipped_skills}