import json
import uuid
import asyncio
from typing import Optional, List
from app.db.database_redis import RedisManager

class BattleRoomRepository:
    """
    배틀 룸 데이터 영속성 관리 및 동시성 제어 (Redis)
    """
    
    @staticmethod
    async def save_room(room_id: str, data: dict, ttl: int = 3600):
        redis = RedisManager.get_client()
        await redis.set(f"room:{room_id}", json.dumps(data), ex=ttl)

    @staticmethod
    async def load_room(room_id: str) -> Optional[dict]:
        redis = RedisManager.get_client()
        data = await redis.get(f"room:{room_id}")
        return json.loads(data) if data else None

    @staticmethod
    async def delete_room(room_id: str):
        redis = RedisManager.get_client()
        keys = [
            f"room:{room_id}",
            f"room:{room_id}:players_list",
            f"room:{room_id}:selections"
        ]
        for key in keys:
            await redis.delete(key)

    @staticmethod
    async def add_player(room_id: str, user_id: int):
        redis = RedisManager.get_client()
        await redis.sadd(f"room:{room_id}:players_list", user_id)

    @staticmethod
    async def remove_player(room_id: str, user_id: int):
        redis = RedisManager.get_client()
        await redis.srem(f"room:{room_id}:players_list", user_id)

    @staticmethod
    async def get_players(room_id: str) -> List[int]:
        redis = RedisManager.get_client()
        members = await redis.smembers(f"room:{room_id}:players_list")
        return [int(m) for m in members]

    @staticmethod
    async def get_player_count(room_id: str) -> int:
        redis = RedisManager.get_client()
        return await redis.scard(f"room:{room_id}:players_list")

    @staticmethod
    async def submit_move(room_id: str, user_id: int, move_id: int):
        redis = RedisManager.get_client()
        await redis.hset(f"room:{room_id}:selections", str(user_id), str(move_id))

    @staticmethod
    async def get_all_selections(room_id: str) -> dict:
        redis = RedisManager.get_client()
        data = await redis.hgetall(f"room:{room_id}:selections")
        return {k: int(v) for k, v in data.items()}

    @staticmethod
    async def clear_selections(room_id: str):
        redis = RedisManager.get_client()
        await redis.delete(f"room:{room_id}:selections")

    # --- Concurrency Control ---
    @staticmethod
    async def acquire_lock(room_id: str, lock_timeout: int = 3) -> bool:
        """
        Redis Atomic Operations를 이용한 분산 락
        """
        redis = RedisManager.get_client()
        lock_key = f"room:{room_id}:turn_lock"
        # NX=True: 키가 없을 때만 설정 (상호 배제)
        # EX=lock_timeout: 데드락 방지를 위한 만료 시간
        is_acquired = await redis.set(lock_key, "locked", nx=True, ex=lock_timeout)
        return bool(is_acquired)

    @staticmethod
    async def release_lock(room_id: str):
        redis = RedisManager.get_client()
        lock_key = f"room:{room_id}:turn_lock"
        await redis.delete(lock_key)

    @staticmethod
    def create_initial_room_data(room_id: str, is_ai_battle: bool = False) -> dict:
        return {
            "room_id": room_id,
            "players": [],
            "character_stats": {},
            "pet_types": {},
            "learned_skills": {},
            "battle_states": {},
            "selections": {},
            "turn_count": 0,
            "field_effects": {"weather": "clear", "location": "stadium"},
            "is_ai_battle": is_ai_battle
        }
