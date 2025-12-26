# backend/app/db/models/user.py

from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.database import Base

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    username: Mapped[str] = mapped_column(String, unique=True, index=True) # 채팅용 아이디 추가
    email: Mapped[str] = mapped_column(String, unique=True, index=True, nullable=True)
    password: Mapped[str] = mapped_column(String) # Hashed password
    nickname = Column(String)
    # 1:1 Relationship with Character
    character: Mapped["Character"] = relationship("Character", back_populates="user", uselist=False, cascade="all, delete-orphan")

    created_at = Column(DateTime(timezone=True), server_default=func.now())