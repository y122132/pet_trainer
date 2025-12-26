import redis.asyncio as redis
import os
from dotenv import load_dotenv

load_dotenv()

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

# Connection Pool (Reusable)
pool = redis.ConnectionPool.from_url(REDIS_URL, decode_responses=True)

class RedisManager:
    @staticmethod
    def get_client() -> redis.Redis:
        """
        Returns an async Redis client from the global connection pool.
        """
        return redis.Redis(connection_pool=pool)

    @staticmethod
    async def close():
        await pool.disconnect()
