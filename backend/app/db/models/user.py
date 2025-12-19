from sqlalchemy import Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.database import Base

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String, unique=True, index=True)
    password: Mapped[str] = mapped_column(String) # Hashed password
    
    # 1:1 Relationship with Character
    character: Mapped["Character"] = relationship("Character", back_populates="user", uselist=False, cascade="all, delete-orphan")