from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, delete
from typing import List

from app.db.database import get_db
from app.db.models.notice import Notice
from app.db.models.user import User
from app.schemas.notice import NoticeCreate, NoticeUpdate, NoticeRead
from app.core.security import get_current_user_id

router = APIRouter(prefix="/notices", tags=["notices"])

async def check_admin(user_id: int, db: AsyncSession):
    stmt = select(User).where(User.id == user_id)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()
    if not user or not user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required"
        )
    return user

@router.get("/", response_model=List[NoticeRead])
async def get_notices(db: AsyncSession = Depends(get_db)):
    """Fetch active notices"""
    stmt = select(Notice).where(Notice.is_active == True).order_by(Notice.created_at.desc(), Notice.id.desc())
    result = await db.execute(stmt)
    return result.scalars().all()

@router.post("/", response_model=NoticeRead, status_code=status.HTTP_201_CREATED)
async def create_notice(
    notice_data: NoticeCreate,
    current_user_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Create a new notice (Admin only)"""
    await check_admin(current_user_id, db)
    
    new_notice = Notice(**notice_data.dict())
    db.add(new_notice)
    await db.commit()
    await db.refresh(new_notice)
    return new_notice

@router.put("/{notice_id}", response_model=NoticeRead)
async def update_notice(
    notice_id: int,
    notice_data: NoticeUpdate,
    current_user_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Update a notice (Admin only)"""
    await check_admin(current_user_id, db)
    
    stmt = select(Notice).where(Notice.id == notice_id)
    result = await db.execute(stmt)
    notice = result.scalar_one_or_none()
    
    if not notice:
        raise HTTPException(status_code=404, detail="Notice not found")
    
    update_data = notice_data.dict(exclude_unset=True)
    for key, value in update_data.items():
        setattr(notice, key, value)
    
    await db.commit()
    await db.refresh(notice)
    return notice

@router.delete("/{notice_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_notice(
    notice_id: int,
    current_user_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Delete a notice (Admin only)"""
    await check_admin(current_user_id, db)
    
    stmt = delete(Notice).where(Notice.id == notice_id)
    result = await db.execute(stmt)
    
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Notice not found")
    
    await db.commit()
    return None
