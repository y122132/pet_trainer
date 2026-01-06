import redis.asyncio as redis
import os
from dotenv import load_dotenv

load_dotenv()

# .env_example 설정과 일치하도록 수정 (유지보수성 향상)
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = os.getenv("REDIS_PORT", "6379")
REDIS_DB = os.getenv("REDIS_DB", "0")

# [Fix] REDIS_URL이 환경 변수에 있다면 우선 사용 (Docker Compose 호환)
REDIS_URL = os.getenv("REDIS_URL", f"redis://{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}")

# Connection Pool (Reusable)
# decode_responses=True는 텍스트 기반의 배틀 로그/채팅 처리에 적합합니다.
pool = redis.ConnectionPool.from_url(REDIS_URL, decode_responses=True)

class RedisManager:
    @staticmethod
    def get_client() -> redis.Redis:
        """
        공용 커넥션 풀에서 비동기 Redis 클라이언트를 반환합니다.
        """
        return redis.Redis(connection_pool=pool, decode_responses=True)

    @staticmethod
    async def close():
        """
        서버 종료 시 커넥션 풀을 안전하게 닫습니다.
        """
        await pool.disconnect()