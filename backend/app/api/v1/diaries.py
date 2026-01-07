from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, func
from sqlalchemy.orm import selectinload
from typing import List, Optional
import os
import shutil
from datetime import datetime

from app.db.database import get_db
from app.db.models.diary import Diary, DiaryLike
from app.db.models.user import User
from app.core.security import get_current_user_id
from pydantic import BaseModel

router = APIRouter(prefix="/diaries", tags=["diaries"])

UPLOAD_DIR = "uploads/diaries"
os.makedirs(UPLOAD_DIR, exist_ok=True)
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp'}

# --- Schemas ---
class DiaryResponse(BaseModel):
    id: int
    user_id: int
    image_url: Optional[str]
    content: str
    tag: str
    created_at: datetime
    likes: int
    isLiked: bool = False # 현재 유저가 좋아요 눌렀는지 여부

class LikeResponse(BaseModel):
    likes: int
    isLiked: bool

# --- Helpers ---
async def _save_upload_file(file: UploadFile, diary_id: int) -> str:
    filename = file.filename
    ext = filename.rsplit('.', 1)[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail=f"File type not allowed: {ext}")
    
    # timestamp for unique filename
    ts = int(datetime.utcnow().timestamp())
    new_filename = f"{diary_id}_{ts}.{ext}"
    file_path = os.path.join(UPLOAD_DIR, new_filename)
    
    with open(file_path, "wb+") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    return f"/{UPLOAD_DIR}/{new_filename}"

# --- Endpoints ---

@router.post("/", response_model=DiaryResponse)
async def create_diary(
    content: str = Form(...),
    tag: str = Form("일상"),
    image: Optional[UploadFile] = File(None),
    db: AsyncSession = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    """일기를 작성합니다. (이미지는 선택사항)"""
    
    # 1. Create Diary Entry
    new_diary = Diary(
        user_id=current_user_id,
        content=content,
        tag=tag,
        created_at=datetime.utcnow()
    )
    db.add(new_diary)
    await db.flush() # ID generation for filename

    # 2. Handle Image Upload if present
    if image:
        try:
            url = await _save_upload_file(image, new_diary.id)
            new_diary.image_url = url
        except Exception as e:
            # If upload fails, rollback? Or just ignore image?
            # Let's simple rollback for consistency
            await db.rollback()
            raise HTTPException(status_code=500, detail=f"Image upload failed: {str(e)}")

    await db.commit()
    await db.refresh(new_diary)
    
    return DiaryResponse(
        id=new_diary.id,
        user_id=new_diary.user_id,
        image_url=new_diary.image_url,
        content=new_diary.content,
        tag=new_diary.tag,
        created_at=new_diary.created_at,
        likes=0,
        isLiked=False
    )

@router.get("/user/{target_user_id}", response_model=List[DiaryResponse])
async def get_user_diaries(
    target_user_id: int,
    db: AsyncSession = Depends(get_db),
    current_user_id: Optional[int] = Depends(get_current_user_id) # Optional auth for public view? Let's require auth for now
):
    """특정 유저의 일기 목록을 조회합니다."""
    
    # Fetch diaries with likes count
    # Note: simple implementation calculating likes in python or via relationship
    stmt = (
        select(Diary)
        .where(Diary.user_id == target_user_id)
        .order_by(desc(Diary.created_at))
        .options(selectinload(Diary.likes)) # Eager load likes
    )
    result = await db.execute(stmt)
    diaries = result.scalars().all()
    
    response = []
    for d in diaries:
        # Check if current user liked this
        is_liked = False
        if current_user_id:
            is_liked = any(like.user_id == current_user_id for like in d.likes)
            
        response.append(DiaryResponse(
            id=d.id,
            user_id=d.user_id,
            image_url=d.image_url,
            content=d.content,
            tag=d.tag,
            created_at=d.created_at,
            likes=len(d.likes),
            isLiked=is_liked
        ))
        
    return response

@router.post("/{diary_id}/like", response_model=LikeResponse)
async def toggle_like(
    diary_id: int,
    db: AsyncSession = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    """좋아요를 토글(설정/해제)합니다."""
    
    # Check if already liked
    stmt = select(DiaryLike).where(
        DiaryLike.diary_id == diary_id,
        DiaryLike.user_id == current_user_id
    )
    result = await db.execute(stmt)
    existing_like = result.scalar_one_or_none()
    
    if existing_like:
        # Unlike
        await db.delete(existing_like)
        is_liked = False
    else:
        # Like
        new_like = DiaryLike(diary_id=diary_id, user_id=current_user_id)
        db.add(new_like)
        is_liked = True
        
    await db.commit()
    
    # Get Updated Count
    count_stmt = select(func.count(DiaryLike.id)).where(DiaryLike.diary_id == diary_id)
    count_res = await db.execute(count_stmt)
    total_likes = count_res.scalar_one()
    
    return LikeResponse(likes=total_likes, isLiked=is_liked)
