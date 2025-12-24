from sqlalchemy import Integer, String, ForeignKey, DateTime, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import JSONB
from datetime import datetime
from typing import Optional
from app.db.database import Base

# --- 캐릭터(Character) 모델 ---
class Character(Base):
    __tablename__ = "characters"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True) # 유저당 하나의 캐릭터 (1:1)
    name: Mapped[str] = mapped_column(String, index=True) # 캐릭터 이름
    status: Mapped[str] = mapped_column(String, default="normal") # 상태 (예: normal, hungry, sleepy)
    pet_type: Mapped[str] = mapped_column(String, default="dog") # 반려동물 종류 (dog, cat 등)
    learned_skills: Mapped[list[int]] = mapped_column(JSONB, default=[]) # 습득한 기술 ID 리스트
    
    # 관계 설정 (Relationships)
    user: Mapped["User"] = relationship("User", back_populates="character")
    
    # 1:1 관계 - uselist=False
    stat: Mapped["Stat"] = relationship("Stat", back_populates="character", uselist=False, cascade="all, delete-orphan")
    
    # 1:N 관계 - 행동 로그
    action_logs: Mapped[list["ActionLog"]] = relationship("ActionLog", back_populates="character", cascade="all, delete-orphan")


# --- 스탯(Stat) 모델 ---
class Stat(Base):
    __tablename__ = "stats"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    character_id: Mapped[int] = mapped_column(ForeignKey("characters.id"), unique=True)
    
    # 주요 능력치
    health: Mapped[int] = mapped_column(Integer, default=100)      # 체력
    happiness: Mapped[int] = mapped_column(Integer, default=50)    # 행복도
    exp: Mapped[int] = mapped_column(Integer, default=0)           # 경험치
    level: Mapped[int] = mapped_column(Integer, default=1)         # 레벨
    strength: Mapped[int] = mapped_column(Integer, default=10)     # 근력
    intelligence: Mapped[int] = mapped_column(Integer, default=10) # 지능
    stamina: Mapped[int] = mapped_column(Integer, default=10)      # 지구력
    defense: Mapped[int] = mapped_column(Integer, default=10)      # 방어력
    luck: Mapped[int] = mapped_column(Integer, default=5)          # 운
    personality: Mapped[str] = mapped_column(String, default="기본") # 성격
    condition: Mapped[int] = mapped_column(Integer, default=100)   # 컨디션 (0-100)
    
    # 훈련 성공 시 획득하는 분배 가능 포인트
    unused_points: Mapped[int] = mapped_column(Integer, default=5)

    character: Mapped["Character"] = relationship("Character", back_populates="stat")


# --- 행동 로그(ActionLog) 모델 ---
class ActionLog(Base):
    __tablename__ = "action_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    character_id: Mapped[int] = mapped_column(ForeignKey("characters.id"))
    
    action_type: Mapped[str] = mapped_column(String) # 수행한 행동 유형 (예: "playing_fetch")
    yolo_result_json: Mapped[dict] = mapped_column(JSONB, nullable=True) # AI 분석 결과 원본 (PostgreSQL JSONB 저장)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow) # 생성 시간

    character: Mapped["Character"] = relationship("Character", back_populates="action_logs")