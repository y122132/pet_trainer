from sqlalchemy import Integer, String, ForeignKey, DateTime, Text, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import JSONB
from datetime import datetime
from app.db.database import Base
import enum

class MemoryType(str, enum.Enum):
    TRAINING = "training"       # 훈련 
    BATTLE = "battle"           # 배틀
    INTERACTION = "interaction" # 쓰다듬기/터치 등
    EVENT = "event"             # 레벨업, 중요 사건

class CharacterMemory(Base):
    """
    개별 기억(Memory)을 저장하는 테이블
    - 원본 대화, 훈련 로그, 배틀 결과 등 의미 있는 단위의 기억
    """
    __tablename__ = "character_memories"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    character_id: Mapped[int] = mapped_column(ForeignKey("characters.id"))
    
    # 기억 유형: 'dialogue', 'training', 'battle', 'event', 'interaction'
    memory_type: Mapped[str] = mapped_column(String, index=True) 
    
    # 내용: LLM이 이해하기 쉬운 서술형 텍스트 (예: "주인님과 비 오는 날 산책을 했다.")
    content: Mapped[str] = mapped_column(Text) 
    
    # 메타데이터: {"weather": "rain", "place": "gym", "opponent": "wolf"}
    # 추후 검색/필터링 용도
    meta_info: Mapped[dict] = mapped_column(JSONB, nullable=True) 
    
    # 중요도: 1(일상) ~ 5(매우 중요)
    importance: Mapped[int] = mapped_column(Integer, default=1)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    # Relationship
    character = relationship("Character", backref="memories")

class MemorySummary(Base):
    """
    기억 요약(Summary) 테이블
    - CharacterMemory가 일정량(예: 10개) 쌓이면 이를 요약하여 저장
    - 장기 기억 검색 시 이 테이블을 우선 조회하여 Context Window 절약
    """
    __tablename__ = "memory_summaries"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    character_id: Mapped[int] = mapped_column(ForeignKey("characters.id"))
    
    # 요약 범위 (Linked List 형태 혹은 범위 지정)
    start_memory_id: Mapped[int] = mapped_column(Integer) # 요약에 포함된 첫 기억 ID
    end_memory_id: Mapped[int] = mapped_column(Integer)   # 요약에 포함된 마지막 기억 ID
    
    # 요약 내용
    summary_text: Mapped[str] = mapped_column(Text)
    
    # 당시 감정/상태 스냅샷 (선택 사항)
    sentiment_snapshot: Mapped[dict] = mapped_column(JSONB, nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    # Relationship
    character = relationship("Character", backref="summaries")
