from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload
from typing import List, Optional
from datetime import datetime
from pydantic import BaseModel

from app.db.database import get_db
from app.db.models.guestbook import GuestbookEntry
from app.db.models.user import User
from app.core.security import get_current_user_id

router = APIRouter(tags=["guestbook"])

# --- Schemas ---
class GuestbookEntryCreate(BaseModel):
    content: str

class GuestbookAuthorResponse(BaseModel):
    id: int
    nickname: str
    pet_type: Optional[str] = "dog" # 기본값

class GuestbookEntryResponse(BaseModel):
    id: int
    user_id: int # 방명록 주인 ID
    author_id: int # 작성자 ID
    content: str
    created_at: datetime
    author: GuestbookAuthorResponse # 작성자 정보

# --- Endpoints ---

@router.post("/user/{target_user_id}", response_model=GuestbookEntryResponse, status_code=status.HTTP_201_CREATED)
async def create_guestbook_entry(
    target_user_id: int,
    entry_create: GuestbookEntryCreate,
    db: AsyncSession = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    """특정 유저의 미니홈피에 방명록을 작성합니다."""
    
    # 1. Check if target user exists
    target_user = await db.get(User, target_user_id)
    if not target_user:
        raise HTTPException(status_code=404, detail="Target user not found")

    # 2. Get author info
    author_user = await db.get(User, current_user_id, options=[selectinload(User.character)])
    if not author_user:
         raise HTTPException(status_code=404, detail="Author (current user) not found")

    # 3. Create new entry
    new_entry = GuestbookEntry(
        user_id=target_user_id,
        author_id=current_user_id,
        content=entry_create.content,
        created_at=datetime.utcnow()
    )
    db.add(new_entry)
    await db.commit()
    await db.refresh(new_entry)
    
    author_pet_type = author_user.character.pet_type if author_user.character else "dog"

    return GuestbookEntryResponse(
        id=new_entry.id,
        user_id=new_entry.user_id,
        author_id=new_entry.author_id,
        content=new_entry.content,
        created_at=new_entry.created_at,
        author=GuestbookAuthorResponse(
            id=author_user.id,
            nickname=author_user.nickname or author_user.username,
            pet_type=author_pet_type,
        )
    )

@router.get("/user/{target_user_id}", response_model=List[GuestbookEntryResponse])
async def get_guestbook_entries(
    target_user_id: int,
    db: AsyncSession = Depends(get_db)
):
    """특정 유저의 방명록 목록을 조회합니다."""
    
    stmt = (
        select(GuestbookEntry)
        .where(GuestbookEntry.user_id == target_user_id)
        .order_by(desc(GuestbookEntry.created_at))
        .options(
            selectinload(GuestbookEntry.author).selectinload(User.character)
        )
    )
    result = await db.execute(stmt)
    entries = result.scalars().all()
    
    response_list = []
    for entry in entries:
        author_pet_type = entry.author.character.pet_type if entry.author.character else "dog"
        response_list.append(
            GuestbookEntryResponse(
                id=entry.id,
                user_id=entry.user_id,
                author_id=entry.author_id,
                content=entry.content,
                created_at=entry.created_at,
                author=GuestbookAuthorResponse(
                    id=entry.author.id,
                    nickname=entry.author.nickname or entry.author.username,
                    pet_type=author_pet_type
                )
            )
        )
        
    return response_list
