from sqladmin.authentication import AuthenticationBackend
from starlette.requests import Request
from sqlalchemy import select
from app.db.database import AsyncSessionLocal
from app.db.models.user import User
from app.core.security import verify_password, create_access_token, verify_token

class AdminAuth(AuthenticationBackend):
    async def login(self, request: Request) -> bool:
        form = await request.form()
        username = form.get("username")
        password = form.get("password")

        async with AsyncSessionLocal() as session:
            stmt = select(User).where(User.username == username)
            result = await session.execute(stmt)
            user = result.scalar_one_or_none()

            # 1. 유저 존재 및 비밀번호 확인
            if not user or not verify_password(password, user.password):
                return False
            
            # 2. 관리자 권한 확인
            if not user.is_admin:
                return False

            # 3. 세션 토큰 설정 (간단히 user_id 저장)
            request.session.update({"user_id": user.id})
            return True

    async def logout(self, request: Request) -> bool:
        request.session.clear()
        return True

    async def authenticate(self, request: Request) -> bool:
        user_id = request.session.get("user_id")
        if not user_id:
            return False
        
        # 옵션: 매 요청마다 DB 체크 (보안 강화)
        # async with AsyncSessionLocal() as session:
        #     user = await session.get(User, user_id)
        #     return user and user.is_admin
        
        return True

authentication_backend = AdminAuth(secret_key="secret_key_for_admin_session")
