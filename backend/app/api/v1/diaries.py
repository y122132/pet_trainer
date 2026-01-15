from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, func
from sqlalchemy.orm import selectinload
from typing import List, Optional
import os
import shutil
from datetime import datetime

from app.db.database import get_db
from app.db.models.diary import Diary, DiaryLike, Comment # Comment 모델 추가
from app.db.models.user import User # User 모델 추가 (댓글 작성자 정보 조회용)
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
    comments_count: int = 0 # 댓글 개수 추가

class LikeResponse(BaseModel):
    likes: int
    isLiked: bool

class CommentCreate(BaseModel): # 댓글 생성 요청 스키마
    content: str
    parent_id: Optional[int] = None

class CommentResponse(BaseModel): # 댓글 응답 스키마
    id: int
    diary_id: int
    user_id: int
    nickname: str # 작성자 닉네임
    pet_type: Optional[str] = None # 작성자 펫 타입 (아바타용)
    content: str
    created_at: datetime
    parent_id: Optional[int] = None
    children: List["CommentResponse"] = []

# --- Helpers ---
import mimetypes

async def _save_upload_file(file: UploadFile, diary_id: int) -> str:
    filename = file.filename
    
    # 1. 파일명에서 확장자 추출 시도
    if '.' in filename:
        ext = filename.rsplit('.', 1)[1].lower()
    else:
        # 2. 확장자가 없으면 MIME 타입을 기반으로 추론
        guessed_ext = mimetypes.guess_extension(file.content_type)
        if guessed_ext:
            ext = guessed_ext.lstrip('.').lower()
        else:
            ext = 'jpg' # 기본값
            
    # jpe -> jpg 변환 등 표준화
    if ext == 'jpe' or ext == 'jpeg':
        ext = 'jpg'

    if ext not in ALLOWED_EXTENSIONS:
        # 허용되지 않는 확장자일 경우, MIME 타입이 이미지라면 강제로 jpg로 취급 시도
        if file.content_type.startswith('image/'):
            ext = 'jpg'
        else:
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
        isLiked=False,
        comments_count=0 # 새 일기는 댓글이 0개
    )

@router.get("/user/{target_user_id}", response_model=List[DiaryResponse])
async def get_user_diaries(
    target_user_id: int,
    db: AsyncSession = Depends(get_db),
    current_user_id: Optional[int] = Depends(get_current_user_id) # Optional auth for public view? Let's require auth for now
):
    """특정 유저의 일기 목록을 조회합니다."""
    
    # Fetch diaries with likes and comments count
    stmt = (
        select(Diary)
        .where(Diary.user_id == target_user_id)
        .order_by(desc(Diary.created_at))
        .options(selectinload(Diary.likes), selectinload(Diary.comments)) # 좋아요와 댓글 모두 Eager load
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
            isLiked=is_liked,
            comments_count=d.comments_count # 댓글 개수 추가
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

# --- Comment Endpoints ---
@router.post("/{diary_id}/comments", response_model=CommentResponse, status_code=status.HTTP_201_CREATED)
async def create_comment(
    diary_id: int,
    comment_create: CommentCreate,
    db: AsyncSession = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    """특정 일기에 댓글을 추가합니다."""
    diary = await db.get(Diary, diary_id)
    if not diary:
        raise HTTPException(status_code=404, detail="Diary not found")

    # User 정보를 Eager Loading으로 가져와 비동기 I/O 문제를 방지합니다.
    stmt = select(User).where(User.id == current_user_id).options(selectinload(User.character))
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if not user:
         raise HTTPException(status_code=404, detail="User not found")

    new_comment = Comment(
        diary_id=diary_id,
        user_id=current_user_id,
        content=comment_create.content,
        parent_id=comment_create.parent_id,
        created_at=datetime.utcnow()
    )
    db.add(new_comment)
    await db.commit()
    await db.refresh(new_comment) # 생성된 ID 및 기타 정보 업데이트
    
    # User.character 관계를 통해 pet_type에 접근
    # character가 None일 경우를 대비해 Optional 체이닝 사용
    pet_type = user.character.pet_type if user.character else None

    return CommentResponse(
        id=new_comment.id,
        diary_id=new_comment.diary_id,
        user_id=new_comment.user_id,
        nickname=user.nickname or user.username, # 닉네임 없으면 유저이름 사용
        pet_type=pet_type,
        content=new_comment.content,
        created_at=new_comment.created_at,
        parent_id=new_comment.parent_id
    )

@router.delete("/{diary_id}/comments/{comment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_comment(
    diary_id: int,
    comment_id: int,
    db: AsyncSession = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    """특정 댓글을 삭제합니다. 댓글 작성자 본인만 삭제할 수 있습니다."""
    
    comment = await db.get(Comment, comment_id)
    
    if not comment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Comment not found")
        
    if comment.diary_id != diary_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Comment does not belong to this diary")

    if comment.user_id != current_user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to delete this comment")
        
    await db.delete(comment)
    await db.commit()
    
    return

@router.get("/{diary_id}/comments", response_model=List[CommentResponse])
async def get_comments_for_diary(
    diary_id: int,
    db: AsyncSession = Depends(get_db)
):
    """특정 일기의 댓글 목록을 조회합니다."""
    diary = await db.get(Diary, diary_id)
    if not diary:
        raise HTTPException(status_code=404, detail="Diary not found")

    stmt = (
        select(Comment)
        .where(Comment.diary_id == diary_id)
        .order_by(Comment.created_at)
        .options(selectinload(Comment.user).selectinload(User.character))
    )
    result = await db.execute(stmt)
    comments = result.scalars().all()

    return [
        CommentResponse(
            id=c.id,
            diary_id=c.diary_id,
            user_id=c.user_id,
            nickname=c.user.nickname or c.user.username,
            pet_type=c.user.character.pet_type if c.user.character else None,
            content=c.content,
            created_at=c.created_at,
            parent_id=c.parent_id
        ) for c in comments
    ]
