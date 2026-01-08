from sqlalchemy import Integer, String, ForeignKey, DateTime, Text, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
from typing import Optional, List, TYPE_CHECKING
from app.db.database import Base

if TYPE_CHECKING:
    from app.db.models.user import User
    # from app.db.models.character import Character # 필요시

class Diary(Base):
    __tablename__ = "diaries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    
    # 일기 내용
    image_url: Mapped[Optional[str]] = mapped_column(String, nullable=True) # 사진은 선택사항
    content: Mapped[str] = mapped_column(Text) # 본문
    tag: Mapped[str] = mapped_column(String, default="일상") # 태그
    
    # 메타데이터
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # 조회 편의성을 위한 역정규화 (선택적) or Join 사용
    # 여기서는 간단하게 likes count는 별도 쿼리나 property로 처리 권장하지만, 
    # 성능을 위해 단순 카운트 컬럼을 둘 수도 있음. 일단은 관계형으로 간다.
    
    # 관계
    user: Mapped["User"] = relationship("User", back_populates="diaries")
    likes: Mapped[List["DiaryLike"]] = relationship("DiaryLike", back_populates="diary", cascade="all, delete-orphan")
    comments: Mapped[List["Comment"]] = relationship("Comment", back_populates="diary", cascade="all, delete-orphan")

    @property
    def like_count(self):
        return len(self.likes)

    @property
    def comments_count(self): # 추가된 속성
        return len(self.comments)

class DiaryLike(Base):
    __tablename__ = "diary_likes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    diary_id: Mapped[int] = mapped_column(ForeignKey("diaries.id"))
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    diary: Mapped["Diary"] = relationship("Diary", back_populates="likes")
    user: Mapped["User"] = relationship("User", back_populates="diary_likes")

class Comment(Base): # 추가된 Comment 모델
    __tablename__ = "comments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    diary_id: Mapped[int] = mapped_column(ForeignKey("diaries.id"))
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))

    # Relationships
    diary: Mapped["Diary"] = relationship("Diary", back_populates="comments")
    user: Mapped["User"] = relationship("User", back_populates="comments")

