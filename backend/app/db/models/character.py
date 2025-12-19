from sqlalchemy import Integer, String, ForeignKey, DateTime, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import JSONB
from datetime import datetime
from typing import Optional
from app.db.database import Base

class Character(Base):
    __tablename__ = "characters"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True)
    name: Mapped[str] = mapped_column(String, index=True)
    status: Mapped[str] = mapped_column(String, default="normal") # e.g., normal, hungry, sleepy
    
    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="character")
    stat: Mapped["Stat"] = relationship("Stat", back_populates="character", uselist=False, cascade="all, delete-orphan")
    action_logs: Mapped[list["ActionLog"]] = relationship("ActionLog", back_populates="character", cascade="all, delete-orphan")


class Stat(Base):
    __tablename__ = "stats"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    character_id: Mapped[int] = mapped_column(ForeignKey("characters.id"), unique=True)
    
    health: Mapped[int] = mapped_column(Integer, default=100)
    happiness: Mapped[int] = mapped_column(Integer, default=50)
    exp: Mapped[int] = mapped_column(Integer, default=0)
    level: Mapped[int] = mapped_column(Integer, default=1)
    strength: Mapped[int] = mapped_column(Integer, default=10)
    intelligence: Mapped[int] = mapped_column(Integer, default=10)
    stamina: Mapped[int] = mapped_column(Integer, default=10)
    unused_points: Mapped[int] = mapped_column(Integer, default=5)

    character: Mapped["Character"] = relationship("Character", back_populates="stat")


class ActionLog(Base):
    __tablename__ = "action_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    character_id: Mapped[int] = mapped_column(ForeignKey("characters.id"))
    
    action_type: Mapped[str] = mapped_column(String) # e.g., "eat", "play", "sleep"
    yolo_result_json: Mapped[dict] = mapped_column(JSONB, nullable=True) # PostgreSQL JSONB
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    character: Mapped["Character"] = relationship("Character", back_populates="action_logs")