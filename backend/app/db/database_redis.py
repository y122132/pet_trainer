# backend/app/db/database_redis.py
import os
import json
import redis.asyncio as redis
from dotenv import load_dotenv

load_dotenv()

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = os.getenv("REDIS_PORT", "6379")
REDIS_DB = os.getenv("REDIS_DB", "0")
REDIS_URL = os.getenv("REDIS_URL", f"redis://{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}")

pool = redis.ConnectionPool.from_url(REDIS_URL, decode_responses=True)

class RedisManager:

    ONLINE_USERS_KEY = "online_users"

    @staticmethod
    def get_client() -> redis.Redis:
        """
        공용 커넥션 풀에서 비동기 Redis 클라이언트를 반환합니다.
        """
        return redis.Redis(connection_pool=pool, decode_responses=True)

    @staticmethod
    async def close():
        await pool.disconnect()

    @classmethod
    async def set_user_online(cls, user_id: int):
        client = cls.get_client()
        await client.sadd(cls.ONLINE_USERS_KEY, user_id)

    @classmethod
    async def set_user_offline(cls, user_id: int):
        client = cls.get_client()
        await client.srem(cls.ONLINE_USERS_KEY, user_id)

    @classmethod
    async def is_user_online(cls, user_id: int) -> bool:
        client = cls.get_client()
        return await client.sismember(cls.ONLINE_USERS_KEY, user_id)

    @classmethod
    async def publish_chat_notification(cls, receiver_id: int, payload: dict):
        client = cls.get_client()
        try:
            message = json.dumps(payload, ensure_ascii=False)
            # return을 추가하여 구독자 수(int)를 반환하도록 합니다.
            return await client.publish(f"user_notify_{receiver_id}", message)
        finally:
            # 클라이언트 연결을 명시적으로 닫기 (연결 풀 반환)
            await client.aclose()