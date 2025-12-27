from pydantic import BaseModel, EmailStr

class UserCreate(BaseModel):
    email: EmailStr
    username: str
    password: str
    nickname: str

class Token(BaseModel):
    access_token: str
    token_type: str
    user_id: int
    
class UserListItem(BaseModel):
    id: int
    nickname: str