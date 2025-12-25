from fastapi import WebSocket, HTTPException, status
from typing import Optional

async def verify_websocket_token(websocket: WebSocket, token: Optional[str]):
    """
    WebSocket 연결 시 토큰을 검증합니다.
    URL 쿼리 파라미터(?token=...) 또는 헤더에서 토큰을 확인합니다.
    
    주의: 현재는 구조만 잡혀있는 상태이며, 모든 토큰을 허용합니다.
    실제 운영 시에는 JWT 디코딩 및 만료 시간 확인 로직을 주석 해제하여 사용하세요.
    """
    if not token:
        # 토큰이 아예 없는 경우
        # 개발 단계에서는 편의를 위해 허용할 수도 있지만, 보안상 거부하는 것이 원칙입니다.
        # await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        # raise HTTPException(status_code=403, detail="Token required")
        pass # [DEV] 개발 편의를 위해 Pass (추후 위 주석 해제)

    # --- [TODO] 실제 JWT 검증 로직 구현 예시 ---
    # try:
    #     payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    #     user_id: str = payload.get("sub")
    #     if user_id is None:
    #         await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
    #         return None
    #     return user_id
    # except JWTError:
    #     await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
    #     return None
    # ---------------------------------------------
    
    # 임시: 토큰이 있으면 유효하다고 가정
    return True
