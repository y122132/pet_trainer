from sqlalchemy import Integer, String, ForeignKey, DateTime, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import datetime
from typing import TYPE_CHECKING
from app.db.database import Base

if TYPE_CHECKING:
    from app.db.models.user import User

class GuestbookEntry(Base):
    __tablename__ = "guestbook_entries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    
    # 방명록 주인 (미니홈피 주인)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True) 
    
    # 방명록 작성자
    author_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    
    # 방명록 내용
    content: Mapped[str] = mapped_column(Text, nullable=False)
    
    # 비밀글 여부
    is_secret: Mapped[bool] = mapped_column(default=False, nullable=False)

    # 메타데이터
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    # --- 관계 ---
    # 이 방명록이 달린 User(주인)
    owner: Mapped["User"] = relationship("User", foreign_keys=[user_id], back_populates="guestbook_entries")
    
    # 이 방명록을 작성한 User(작성자)
    author: Mapped["User"] = relationship("User", foreign_keys=[author_id], back_populates="authored_guestbook_entries")

