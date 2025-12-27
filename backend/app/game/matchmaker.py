import asyncio
import uuid
from typing import List, Dict, Optional
from fastapi import WebSocket

class Matchmaker:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(Matchmaker, cls).__new__(cls)
            cls._instance.queue = [] # List of (user_id, websocket)
            cls._instance.active_matches = {} # room_id -> [user_id, user_id]
        return cls._instance

    async def add_to_queue(self, user_id: int, websocket: WebSocket):
        """대기열에 유저 추가 및 매칭 시도"""
        # 이미 대기열에 있으면 제거 (갱신)
        self.remove_from_queue(user_id)
        
        self.queue.append((user_id, websocket))
        print(f"[Matchmaker] User {user_id} added to queue. Queue size: {len(self.queue)}")
        
        await self.check_match()

    def remove_from_queue(self, user_id: int):
        """대기열에서 유저 제거"""
        self.queue = [p for p in self.queue if p[0] != user_id]
        print(f"[Matchmaker] User {user_id} removed from queue.")

    async def check_match(self):
        """대기열을 확인하여 2명이 모이면 매칭 성사"""
        if len(self.queue) >= 2:
            # 2명 추출
            player1 = self.queue.pop(0)
            player2 = self.queue.pop(0)
            
            p1_id, p1_ws = player1
            p2_id, p2_ws = player2
            
            # 고유 Room ID 생성
            room_id = str(uuid.uuid4())
            
            print(f"[Matchmaker] Match found! Room: {room_id}, Players: {p1_id} vs {p2_id}")
            
            # 매칭 정보 전송
            match_data = {
                "type": "MATCH_FOUND",
                "room_id": room_id,
                "opponent_id": p2_id # p1에게는 p2가 상대
            }
            try:
                await p1_ws.send_json(match_data)
            except Exception as e:
                print(f"[Matchmaker] Failed to notify p1: {e}")
                
            match_data["opponent_id"] = p1_id # p2에게는 p1이 상대
            try:
                await p2_ws.send_json(match_data)
            except Exception as e:
                print(f"[Matchmaker] Failed to notify p2: {e}")

matchmaker = Matchmaker()
