# backend/app/db/models/chat_data.py
from sqlalchemy.sql import func
from app.db.database import Base
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Boolean

class ChatMessage(Base):
    __tablename__ = "chat_messages"

    id = Column(Integer, primary_key=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    receiver_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    message = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    is_read = Column(Boolean, default=False)