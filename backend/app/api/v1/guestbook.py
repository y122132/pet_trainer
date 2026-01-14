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
    is_secret: Optional[bool] = False

class GuestbookAuthorResponse(BaseModel):
    id: int
    nickname: str
    pet_type: Optional[str] = "dog" # 기본값

class GuestbookEntryResponse(BaseModel):
    id: int
    user_id: int # 방명록 주인 ID
    author_id: int # 작성자 ID
    content: str
    is_secret: bool # 비밀글 여부
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

    # 2. Create new entry
    new_entry = GuestbookEntry(
        user_id=target_user_id,
        author_id=current_user_id,
        content=entry_create.content,
        is_secret=entry_create.is_secret,
        created_at=datetime.utcnow()
    )
    db.add(new_entry)
    await db.commit()

    # 3. Re-fetch the new entry with all relationships loaded for the response
    # This ensures the 'author' and 'author.character' data is included
    result = await db.execute(
        select(GuestbookEntry)
        .where(GuestbookEntry.id == new_entry.id)
        .options(selectinload(GuestbookEntry.author).selectinload(User.character))
    )
    final_entry = result.scalar_one_or_none()

    if not final_entry:
        raise HTTPException(status_code=500, detail="Could not retrieve created entry")
    
    # Let FastAPI serialize the ORM model using the response_model
    return final_entry

@router.get("/user/{target_user_id}", response_model=List[GuestbookEntryResponse])
async def get_guestbook_entries(
    target_user_id: int,
    db: AsyncSession = Depends(get_db),
    current_user_id: Optional[int] = Depends(get_current_user_id)
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
        # 방명록 작성자가 삭제되는 등 데이터 불일치 상황에 대한 방어 코드
        if not entry.author:
            continue

        content = entry.content
        # 비밀글 처리
        if entry.is_secret:
            # 로그인하지 않았거나, 주인이 아니고, 작성자도 아니면 내용을 숨김
            if not current_user_id or (current_user_id != entry.user_id and current_user_id != entry.author_id):
                content = "🔒 비밀글입니다."

        author_pet_type = entry.author.character.pet_type if entry.author.character else "dog"
        response_list.append(
            GuestbookEntryResponse(
                id=entry.id,
                user_id=entry.user_id,
                author_id=entry.author_id,
                content=content,
                is_secret=entry.is_secret,
                created_at=entry.created_at,
                author=GuestbookAuthorResponse(
                    id=entry.author.id,
                    nickname=entry.author.nickname or entry.author.username,
                    pet_type=author_pet_type
                )
            )
        )
        
    return response_list
