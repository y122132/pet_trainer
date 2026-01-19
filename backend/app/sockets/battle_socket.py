# backend/app/sockets/battle_socket.py
import json
import uuid
import asyncio
import random
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from typing import Dict, Optional
from app.services import char_service
from app.game.matchmaker import matchmaker
from app.game.game_assets import MOVE_DATA
from app.db.database import AsyncSessionLocal
from app.db.models.character import Character, Stat
from app.core.security import verify_websocket_token
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.game.battle_manager import BattleState

# [Refactored Imports]
from app.repositories.battle_repository import BattleRoomRepository
from app.game.battle_event_handler import BattleEventHandler
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from typing import Dict, Optional
from app.services import char_service
from app.game.matchmaker import matchmaker
from app.game.game_assets import MOVE_DATA
from app.db.database import AsyncSessionLocal
from app.db.models.character import Character, Stat
from app.core.security import verify_websocket_token
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.game.battle_manager import BattleState

# [Refactored Imports]
from app.repositories.battle_repository import BattleRoomRepository
from app.game.battle_event_handler import BattleEventHandler

router = APIRouter()

# --- 웹소켓 연결 관리 클래스 ---
class BattleConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, Dict[int, WebSocket]] = {}

    async def connect(self, room_id: str, user_id: int, websocket: WebSocket):
        if room_id not in self.active_connections:
            self.active_connections[room_id] = {}
        self.active_connections[room_id][user_id] = websocket

    def disconnect(self, room_id: str, user_id: int):
        if room_id in self.active_connections:
            if user_id in self.active_connections[room_id]:
                del self.active_connections[room_id][user_id]
            if not self.active_connections[room_id]:
                del self.active_connections[room_id]

    async def broadcast(self, room_id: str, message: dict):
        if room_id in self.active_connections:
            targets = list(self.active_connections[room_id].items())
            for uid, ws in targets:
                try:
                    if ws.client_state.value == 1:
                        await ws.send_json(message)
                except:
                    self.disconnect(room_id, uid)

    async def send_to_user(self, room_id: str, user_id: int, message: dict):
        ws = self.active_connections.get(room_id, {}).get(user_id)
        if ws:
            try:
                await ws.send_json(message)
            except: pass

manager = BattleConnectionManager()

# --- [1] 매치메이킹 엔드포인트 ---
@router.websocket("/ws/battle/matchmaking/{user_id}")
async def matchmaking_endpoint(websocket: WebSocket, user_id: int, token: str | None = None):
    try:
        await verify_websocket_token(websocket, token)
        await websocket.accept()

        async with AsyncSessionLocal() as db:
            char_res = await db.execute(select(Character).where(Character.user_id == user_id))
            char = char_res.scalar_one_or_none()
            if not char:
                await websocket.close(code=4004)
                return
            
            stat_res = await db.execute(select(Stat).where(Stat.character_id == char.id))
            char_stat = stat_res.scalar_one_or_none()
            
            if not char_stat or char_stat.level < 10:
                await websocket.send_json({
                    "type": "ERROR", 
                    "code": "LEVEL_LOW", 
                    "message": f"Lv.10부터 가능합니다. (현재: {char_stat.level if char_stat else 1})"
                })
                try:
                    while True:
                        data = await websocket.receive_text()
                        if data == "EXIT": break
                except WebSocketDisconnect: pass
                return

        await matchmaker.add_to_queue(user_id, websocket)

        while True:
            try:
                data = await asyncio.wait_for(websocket.receive_text(), timeout=1.0)
                if data == "CANCEL": break
                if data == "AI_BATTLE":
                    room_id = str(uuid.uuid4())
                    init_data = BattleRoomRepository.create_initial_room_data(room_id, is_ai_battle=True)
                    await BattleRoomRepository.save_room(room_id, init_data)
                    await websocket.send_json({"type": "MATCH_FOUND", "room_id": room_id, "opponent_id": 0})
                    break
            except asyncio.TimeoutError:
                continue
    except WebSocketDisconnect:
        pass
    finally:
        matchmaker.remove_from_queue(user_id)

# --- [2] 배틀 엔드포인트 ---
@router.websocket("/ws/battle/{room_id}/{user_id}")
async def battle_endpoint(websocket: WebSocket, room_id: str, user_id: int, token: str | None = None):
    print(f"\n🔥 [BATTLE_DEBUG] Connect - User: {user_id}, Room: {room_id}")
    
    if user_id <= 0:
        await websocket.close(code=4000)
        return
    try:
        await verify_websocket_token(websocket, token)
        await websocket.accept()
        await manager.connect(room_id, user_id, websocket)

        # 초기화: Event Handler 생성
        handler = BattleEventHandler(manager, room_id)
        
        # 플레이어 등록
        await BattleRoomRepository.add_player(room_id, user_id)

        # DB 읽기 및 초기 데이터 세팅
        async with AsyncSessionLocal() as db:
            char_res = await db.execute(
                select(Character).options(selectinload(Character.stat)).where(Character.user_id == user_id)
            )
            char = char_res.scalar_one_or_none()
            if not char:
                await websocket.close(code=4004)
                return
            stat = char.stat

            # Lock 없이 읽고 쓰기 (초기 데이터 주입은 경쟁이 적음, 하지만 안전하게 하려면 Lock 필요할수도)
            # 여기서는 편의상 Lock 없이 진행하되, 데이터가 없으면 새로 생성하는 구조 유지
            room_data = await BattleRoomRepository.load_room(room_id) or BattleRoomRepository.create_initial_room_data(room_id)
            uid_str = str(user_id)
            
            # 내 정보 기입
            room_data["character_stats"][uid_str] = {k: v for k, v in stat.__dict__.items() if not k.startswith('_') and isinstance(v, (int, float, str, bool, list, dict))}
            room_data["pet_types"][uid_str] = char.pet_type
            room_data["learned_skills"][uid_str] = char.learned_skills or [1]

            if "image_urls" not in room_data: room_data["image_urls"] = {}
            room_data["image_urls"][uid_str] = {
                "front": char.front_url, "back": char.back_url, "side": char.side_url, "face": char.face_url,
                "front_left": char.front_left_url, "front_right": char.front_right_url,
                "back_left": char.back_left_url, "back_right": char.back_right_url,
            }

            if uid_str not in room_data["battle_states"]:
                room_data["battle_states"][uid_str] = BattleState(max_hp=stat.health, current_hp=stat.health).to_dict()

            # AI 봇 설정
            if room_data.get("is_ai_battle") and "0" not in room_data["battle_states"]:
                if 0 not in room_data["players"]: room_data["players"].append(0)
                room_data["character_stats"]["0"] = room_data["character_stats"][uid_str]
                
                # [Refactor] Random AI Type
                ai_type = random.choice(["dog", "cat", "parrot"])
                room_data["pet_types"]["0"] = ai_type

                room_data["learned_skills"]["0"] = [5, 15, 30] # 곰 봇 스킬 (그대로 유지)
                room_data["battle_states"]["0"] = room_data["battle_states"][uid_str]
                # Image URLs for bot (Empty or Default)
                room_data["image_urls"]["0"] = {"front":"", "back":"", "side":"", "face":"", "front_left":"", "front_right":"", "back_left":"", "back_right":""}

            # 플레이어 리스트 동기화
            actual_members = await BattleRoomRepository.get_players(room_id)
            all_ids = set(actual_members)
            if room_data.get("is_ai_battle"): all_ids.add(0)
            room_data["players"] = list(all_ids)

            await BattleRoomRepository.save_room(room_id, room_data)

        await manager.broadcast(room_id, {"type": "JOIN", "user_id": user_id, "message": f"User {user_id} joined."})

        # 배틀 시작 체크
        if len(room_data["players"]) >= 2:
            # 약간의 지연 후 체크
            await asyncio.sleep(0.5)
            final_check = await BattleRoomRepository.load_room(room_id)
            if all(str(p) in final_check["battle_states"] for p in final_check["players"]):
                await start_battle_check_refactored(room_id)

        # 메인 루프
        while True:
            msg = await websocket.receive_json()
            
            if msg.get("action") == "select_move":
                move_id = msg.get("move_id")
                await handler.handle_select_move(user_id, move_id)
                
            elif msg.get("action") == "surrender":
                 await handler.handle_surrender(user_id)

    except WebSocketDisconnect:
        manager.disconnect(room_id, user_id)
        # 기권/퇴장 처리 핸들러 직접 호출 (Event Handler 활용)
         # 핸들러 인스턴스 재생성 필요할 수 있음 (scope issue)
        temp_handler = BattleEventHandler(manager, room_id)
        await temp_handler.handle_surrender(user_id) # 퇴장은 기권으로 처리
        
    except Exception as e:
        print(f"⚠️ Error: {e}")
        import traceback
        traceback.print_exc()
        if websocket.client_state.value == 1:
            try: await websocket.close(code=4000)
            except: pass
    finally:
        await BattleRoomRepository.remove_player(room_id, user_id)
        remaining = await BattleRoomRepository.get_player_count(room_id)
        if remaining == 0:
            await BattleRoomRepository.delete_room(room_id)

async def start_battle_check_refactored(room_id: str):
    try:
        room_data = await BattleRoomRepository.load_room(room_id)
        if not room_data: return
        
        stats_info = {}
        for uid in room_data["players"]:
            uid_str = str(uid)
            user_battle_state = room_data.get("battle_states", {}).get(uid_str, {})
            current_hp = user_battle_state.get("current_hp", 100)
            max_hp = user_battle_state.get("max_hp", 100)

            details = []
            sids = room_data.get("learned_skills", {}).get(uid_str, [1])
            for sid in sids:
                md = MOVE_DATA.get(sid)
                if md:
                    pp_dict = user_battle_state.get("pp", {})
                    details.append({
                        "id": sid, "name": md["name"], "type": md["type"],
                        "power": md["power"], "desc": md["description"],
                        "max_pp": md.get("max_pp", 20),
                        "pp": pp_dict.get(str(sid), md.get("max_pp", 20))
                    })
            
            imgs = room_data.get("image_urls", {}).get(uid_str, {})
            
            stats_info[uid_str] = {
                "id": int(uid), "hp": current_hp, "max_hp": max_hp,
                "name": f"User {uid_str}",
                "pet_type": room_data.get("pet_types", {}).get(uid_str, "dog"),
                "skills": details,
                "front_url": imgs.get("front") or "", "back_url": imgs.get("back") or "",
                "side_url": imgs.get("side") or "", "face_url": imgs.get("face") or "",
                "front_left_url": imgs.get("front_left") or "", "front_right_url": imgs.get("front_right") or "",
                "back_left_url": imgs.get("back_left") or "", "back_right_url": imgs.get("back_right") or "",
            }
        
        await manager.broadcast(room_id, {
            "type": "BATTLE_START",
            "players": stats_info,
            "message": "Battle Started!"
        })

    except Exception as e:
        print(f"🔥 [BATTLE_CRASH] Start Check Error: {e}")