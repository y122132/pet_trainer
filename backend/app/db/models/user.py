#backend/app/db/models/user.py
from datetime import datetime
from app.db.database import Base
from typing import Optional, TYPE_CHECKING
from sqlalchemy import Column, Integer, String, Boolean, DateTime
from sqlalchemy.orm import Mapped, mapped_column, relationship

# 순환 참조 방지를 위한 타입 체크
if TYPE_CHECKING:
    from app.db.models.character import Character
    from app.db.models.friendship import Friendship
    from app.db.models.diary import Diary, DiaryLike, Comment # Comment 추가
    from app.db.models.guestbook import GuestbookEntry

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, index=True, nullable=False)
    nickname: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    password: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True) # network에서 추가된 필드
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False) # 관리자 권한
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow) # develop의 생성일자 유지
    
    # 1:1 Relationship with Character
    character: Mapped["Character"] = relationship(
        "Character", 
        back_populates="user", 
        uselist=False, 
        cascade="all, delete-orphan"
    )

    # Friendships
    sent_requests: Mapped[list["Friendship"]] = relationship(
        "Friendship",
        foreign_keys="Friendship.requester_id",
        back_populates="requester",
        cascade="all, delete-orphan"
    )
    
    received_requests: Mapped[list["Friendship"]] = relationship(
        "Friendship",
        foreign_keys="Friendship.receiver_id",
        back_populates="receiver",
        cascade="all, delete-orphan"
    )

    # Diaries
    diaries: Mapped[list["Diary"]] = relationship("Diary", back_populates="user", cascade="all, delete-orphan")
    diary_likes: Mapped[list["DiaryLike"]] = relationship("DiaryLike", back_populates="user", cascade="all, delete-orphan")
    comments: Mapped[list["Comment"]] = relationship("Comment", back_populates="user", cascade="all, delete-orphan") # 추가

    # Guestbook
    guestbook_entries: Mapped[list["GuestbookEntry"]] = relationship("GuestbookEntry", foreign_keys="GuestbookEntry.user_id", back_populates="owner", cascade="all, delete-orphan")
    authored_guestbook_entries: Mapped[list["GuestbookEntry"]] = relationship("GuestbookEntry", foreign_keys="GuestbookEntry.author_id", back_populates="author", cascade="all, delete-orphan")