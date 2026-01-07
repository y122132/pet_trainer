import asyncio
import uuid
import json
from typing import List, Dict, Optional
from fastapi import WebSocket
from app.db.database_redis import RedisManager

class Matchmaker:
    _instance = None
    MATCHMAKING_QUEUE_KEY = "battle_match_queue"
    MATCH_CHANNEL = "battle_match_notifications"

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(Matchmaker, cls).__new__(cls)
            cls._instance.local_websockets: Dict[int, WebSocket] = {}
            # Pub/Sub 리스너는 외부에서 시작하거나 __init__ 대신 별도 메서드로 실행 필요
        return cls._instance

    async def start_listener(self):
        """Redis Pub/Sub을 구독하여 다른 서버 인스턴스에서의 매칭 성공 알림을 처리합니다."""
        redis = RedisManager.get_client()
        pubsub = redis.pubsub()
        await pubsub.subscribe(self.MATCH_CHANNEL)
        
        print(f"[Matchmaker] Started listening on {self.MATCH_CHANNEL}")
        
        async for message in pubsub.listen():
            if message["type"] == "message":
                data = json.loads(message["data"])
                target_user_id = data.get("target_user_id")
                match_data = data.get("match_data")
                
                if target_user_id in self.local_websockets:
                    ws = self.local_websockets[target_user_id]
                    try:
                        await ws.send_json(match_data)
                        print(f"[Matchmaker] Notified local user {target_user_id} via Pub/Sub")
                    except Exception as e:
                        print(f"[Matchmaker] Error notifying user {target_user_id}: {e}")

    async def add_to_queue(self, user_id: int, websocket: WebSocket):
        """대기열(Redis)에 유저 추가 및 매칭 시도"""
        redis = RedisManager.get_client()
        
        # 1. 로컬 웹소켓 저장
        self.local_websockets[user_id] = websocket
        
        # 2. Redis 대기열에 추가 (이미 있다면 무시하거나 갱신 - 여기선 간단히 중복 방지 없이 추가)
        # 실제로는 SISMEMBER 등으로 중복 체크 후 LPUSH 하는 것이 안전함
        is_queued = await redis.sismember("queued_users_set", user_id)
        if not is_queued:
            await redis.sadd("queued_users_set", user_id)
            await redis.lpush(self.MATCHMAKING_QUEUE_KEY, user_id)
            print(f"[Matchmaker] User {user_id} added to Redis queue.")
        else:
            print(f"[Matchmaker] User {user_id} is already in queue.")
        
        # 3. 매칭 체크
        await self.check_match()

    def remove_from_queue(self, user_id: int):
        """대기열에서 제거 (연결 종료 시)"""
        if user_id in self.local_websockets:
            del self.local_websockets[user_id]
        
        # Redis에서의 제거는 LREM을 사용해야 하므로 비동기 작업이 필요함. 
        # 여기서는 동기 함수이므로 루프에서 처리하거나 별도 비동칙 래퍼 호출 필요.
        # websocket_endpoint에서 직접 비동기로 부르는 것이 나음.
        pass

    async def remove_from_queue_async(self, user_id: int):
        redis = RedisManager.get_client()
        await redis.lrem(self.MATCHMAKING_QUEUE_KEY, 0, user_id)
        await redis.srem("queued_users_set", user_id)
        if user_id in self.local_websockets:
            del self.local_websockets[user_id]
        print(f"[Matchmaker] User {user_id} removed from Redis queue.")

    async def check_match(self):
        """대기열을 확인하여 2명이 모이면 매칭 성사"""
        redis = RedisManager.get_client()
        
        # 최소 2명이 있는지 확인
        queue_len = await redis.llen(self.MATCHMAKING_QUEUE_KEY)
        if queue_len >= 2:
            # 원자적으로 2명 가져오기 (실제로는 완전 원자적이지 않을 수 있지만 간단히 구현)
            user1_id = await redis.rpop(self.MATCHMAKING_QUEUE_KEY)
            user2_id = await redis.rpop(self.MATCHMAKING_QUEUE_KEY)
            
            if not user1_id or not user2_id:
                # 한 명만 뽑힌 경우 다시 넣거나 처리 (여기선 생략)
                return

            # Set에서도 제거
            await redis.srem("queued_users_set", int(user1_id), int(user2_id))
            
            p1_id, p2_id = int(user1_id), int(user2_id)
            room_id = str(uuid.uuid4())
            
            print(f"[Matchmaker] Match found! Room: {room_id}, Players: {p1_id} vs {p2_id}")
            
            # 각각에게 알림 전송
            for me_id, opp_id in [(p1_id, p2_id), (p2_id, p1_id)]:
                match_data = {
                    "type": "MATCH_FOUND",
                    "room_id": room_id,
                    "opponent_id": opp_id
                }
                
                # 로컬에 있으면 직접 전송
                if me_id in self.local_websockets:
                    try:
                        await self.local_websockets[me_id].send_json(match_data)
                    except:
                        pass
                else:
                    # 타 서버에 있을 수 있으므로 Pub/Sub 발행
                    await redis.publish(self.MATCH_CHANNEL, json.dumps({
                        "target_user_id": me_id,
                        "match_data": match_data
                    }))

matchmaker = Matchmaker()
