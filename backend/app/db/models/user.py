# [병합본] backend/app/db/models/user.py
from sqlalchemy import Column, Integer, String, Boolean, DateTime
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.database import Base
from datetime import datetime
from typing import Optional, TYPE_CHECKING

# 순환 참조 방지를 위한 타입 체크
if TYPE_CHECKING:
    from app.db.models.character import Character

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, index=True, nullable=False)
    nickname: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    password: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True) # network에서 추가된 필드
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow) # develop의 생성일자 유지
    
    # 1:1 Relationship with Character
    character: Mapped["Character"] = relationship(
        "Character", 
        back_populates="user", 
        uselist=False, 
        cascade="all, delete-orphan"
    )