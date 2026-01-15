# backend/app/sockets/battle_socket.py
import json
import uuid
import random
import asyncio
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from typing import Dict, Optional
from app.services import char_service
from app.game.matchmaker import matchmaker
from app.game.game_assets import MOVE_DATA
from app.db.database import AsyncSessionLocal
from app.db.database_redis import RedisManager
from app.db.models.character import Character, Stat
from app.core.security import verify_websocket_token
from app.game.battle_calculator import BattleCalculator
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.game.battle_manager import BattleManager, BattleState

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
            await ws.send_json(message)

manager = BattleConnectionManager()

# --- 헬퍼 함수 ---
async def save_room_state(room_id: str, data: dict):
    redis = RedisManager.get_client()
    await redis.set(f"room:{room_id}", json.dumps(data), ex=3600)

async def load_room_state(room_id: str) -> Optional[dict]:
    redis = RedisManager.get_client()
    data = await redis.get(f"room:{room_id}")
    return json.loads(data) if data else None

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

async def handle_forfeit(room_id: str, leaver_id: int):
    """유저가 나갔을 때 남은 유저 승리 처리"""
    room_data = await load_room_state(room_id)
    if not room_data: return

    winner_id = None
    for p_id in room_data["players"]:
        if p_id != leaver_id:
            winner_id = p_id
            break

    if winner_id is not None and winner_id != 0:
        await manager.send_to_user(room_id, winner_id, {
            "type": "GAME_OVER",
            "result": "WIN",
            "reason": "opponent_fled",
            "message": "상대방이 대전을 포기했습니다."
        })
        async with AsyncSessionLocal() as db:
            await char_service.process_battle_result(db, winner_id, leaver_id)
        await delete_room_state(room_id)

async def delete_room_state(room_id: str):
    """방과 관련된 모든 Redis 임시 데이터를 삭제합니다."""
    redis = RedisManager.get_client()
    keys = [
        f"room:{room_id}",
        f"room:{room_id}:players_list",
        f"room:{room_id}:selections"
    ]
    for key in keys:
        await redis.delete(key)
    print(f"🧹 [Cleanup] Room {room_id} data purged.")

# --- [1] 매치메이킹 엔드포인트 (레벨 제한 포함) ---
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
            
            # 🔴 레벨 제한 체크 로직 (Lv.10 미만 입장 불가)
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
                # 🔴 비동기 타임아웃 대기로 매칭 신호 수신 보장
                data = await asyncio.wait_for(websocket.receive_text(), timeout=1.0)
                if data == "CANCEL": break
                if data == "AI_BATTLE":
                    room_id = str(uuid.uuid4())
                    await save_room_state(room_id, create_initial_room_data(room_id, is_ai_battle=True))
                    await websocket.send_json({"type": "MATCH_FOUND", "room_id": room_id, "opponent_id": 0})
                    break
            except asyncio.TimeoutError:
                continue
    except WebSocketDisconnect:
        pass
    finally:
        matchmaker.remove_from_queue(user_id)

# --- [2] 배틀 엔드포인트 (데이터 동기화 및 기권 처리 포함) ---
@router.websocket("/ws/battle/{room_id}/{user_id}")
async def battle_endpoint(websocket: WebSocket, room_id: str, user_id: int, token: str | None = None):
    print(f"\n🔥 [BATTLE_DEBUG] =========================================")
    print(f"🚩 접속 시도 - 유저ID: {user_id}")
    print(f"🚩 접속 시도 - 방ID(URL에서 추출): {room_id}")
    print(f"========================================================\n")
    if user_id <= 0:
        print(f"❌ [BATTLE_REJECT] 비정상적인 유저 ID: {user_id} (방ID: {room_id})")
        await websocket.close(code=4000)
        return
    try:
        await verify_websocket_token(websocket, token)
        await websocket.accept()
        await manager.connect(room_id, user_id, websocket)

        redis = RedisManager.get_client()
        players_set_key = f"room:{room_id}:players_list"
        await redis.sadd(players_set_key, user_id)

        async with AsyncSessionLocal() as db:
            char_res = await db.execute(
                select(Character).options(selectinload(Character.stat)).where(Character.user_id == user_id)
            )
            char = char_res.scalar_one_or_none()
            if not char:
                await websocket.close(code=4004)
                return
            stat = char.stat

            # 🔴 데이터 덮어쓰기 방지를 위한 원자적 업데이트
            room_data = await load_room_state(room_id) or create_initial_room_data(room_id)
            uid_str = str(user_id)
            
            current_players = await redis.smembers(players_set_key)
            print(f"📢 [BATTLE_DEBUG] 방({room_id}) 현재 접속 인원: {current_players}")

            # 내 정보 기입
            room_data["character_stats"][uid_str] = {k: v for k, v in stat.__dict__.items() if not k.startswith('_') and isinstance(v, (int, float, str, bool, list, dict))}
            room_data["pet_types"][uid_str] = char.pet_type
            room_data["learned_skills"][uid_str] = char.learned_skills or [1]

            if "image_urls" not in room_data: room_data["image_urls"] = {}
            room_data["image_urls"][uid_str] = {
                "front": char.front_url,
                "back": char.back_url,
                "side": char.side_url,
                "face": char.face_url
            }

            if uid_str not in room_data["battle_states"]:
                room_data["battle_states"][uid_str] = BattleState(max_hp=stat.health, current_hp=stat.health).to_dict()

            # AI 봇 설정 복구
            if room_data.get("is_ai_battle") and "0" not in room_data["battle_states"]:
                room_data["players"].append(0)
                room_data["character_stats"]["0"] = room_data["character_stats"][uid_str]
                room_data["pet_types"]["0"] = "bear"
                room_data["learned_skills"]["0"] = [5, 15, 30]
                room_data["battle_states"]["0"] = room_data["battle_states"][uid_str]

            # 플레이어 리스트 최종 동기화
            actual_members = await redis.smembers(players_set_key)
            all_ids = set([int(m) for m in actual_members])
            if room_data.get("is_ai_battle"): all_ids.add(0)
            room_data["players"] = list(all_ids)

            await save_room_state(room_id, room_data)

        await manager.broadcast(room_id, {"type": "JOIN", "user_id": user_id, "message": f"User {user_id} joined."})

        # 🔴 배틀 시작 최종 확인 (양측 데이터 무결성 검사)
        if len(room_data["players"]) >= 2:
            print(f"⚔️ [BATTLE_DEBUG] 방({room_id}) 인원 충족(2명). 배틀 시작 검사 진입...")
            await asyncio.sleep(0.5) # 동기화 시간 확보
            final_check = await load_room_state(room_id)

            for p in final_check["players"]:
                has_data = str(p) in final_check["battle_states"]
                print(f"   - 플레이어 {p} 데이터 존재 여부: {has_data}")

            if all(str(p) in final_check["battle_states"] for p in final_check["players"]):
                await start_battle_check(room_id)
            else:
                print(f"⚠️ [BATTLE_DEBUG] 방({room_id}) 인원은 맞지만 데이터 동기화가 아직 안됨.")

        while True:
            msg = await websocket.receive_json()
            if msg.get("action") == "select_move":
                move_id = msg.get("move_id")
                await redis.hset(f"room:{room_id}:selections", uid_str, move_id)

                if room_data.get("is_ai_battle"):
                    bot_move = random.choice(room_data["learned_skills"].get("0", [5]))
                    await redis.hset(f"room:{room_id}:selections", "0", str(bot_move))

                all_selections = await redis.hgetall(f"room:{room_id}:selections")
                if len(all_selections) >= 2:
                    current_room = await load_room_state(room_id)
                    current_room["selections"] = {k: int(v) for k, v in all_selections.items()}
                    await save_room_state(room_id, current_room)
                    await redis.delete(f"room:{room_id}:selections")
                    await process_turn_redis(room_id)
                else:
                    await manager.send_to_user(room_id, user_id, {"type": "WAITING"})

    except WebSocketDisconnect:
        manager.disconnect(room_id, user_id)
        # 🔴 기권 처리 실행
        await handle_forfeit(room_id, user_id)
    except Exception as e:
        print(f"⚠️ Error: {e}")
        if websocket.client_state.value == 1:
            await websocket.close(code=4000)
    finally:
        redis = RedisManager.get_client()
        # 플레이어 리스트에서 나간 유저 제거
        await redis.srem(f"room:{room_id}:players_list", user_id)
        # 남은 인원 확인
        remaining = await redis.scard(f"room:{room_id}:players_list")
        if remaining == 0:
            await delete_room_state(room_id)
        
async def start_battle_check(room_id: str):
    try:
        room_data = await load_room_state(room_id)
        if not room_data:
            print(f"❌ [BATTLE_ERROR] 방 데이터를 찾을 수 없음: {room_id}")
            return
        
        stats_info = {}
        for uid in room_data["players"]:
            uid_str = str(uid)
            
            # 1. 배틀 상태 안전하게 가져오기 (기본값 100)
            user_battle_state = room_data.get("battle_states", {}).get(uid_str, {})
            current_hp = user_battle_state.get("current_hp", 100)
            max_hp = user_battle_state.get("max_hp", 100)

            # 2. 스킬 상세 정보 (비어있어도 진행되게)
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
            
            # 3. 이미지 데이터 (None일 경우 빈 문자열 처리 - 프론트 크래시 방지)
            imgs = room_data.get("image_urls", {}).get(uid_str, {})

            # 🔴 여기서 하나라도 Key가 없으면 KeyError로 서버가 죽습니다. .get()으로 방어!
            stats_info[uid_str] = {
                "id": int(uid),
                "hp": current_hp,
                "max_hp": max_hp,
                "name": f"User {uid_str}",
                "pet_type": room_data.get("pet_types", {}).get(uid_str, "dog"),
                "skills": details,
                "front_url": imgs.get("front") or "",
                "back_url": imgs.get("back") or "",
                "side_url": imgs.get("side") or "",
                "face_url": imgs.get("face") or "",
            }
        
        # 4. 데이터 전송 시도
        print(f"🚀 [BATTLE_DEBUG] 방({room_id}) 데이터 조립 완료. 전송 시도...")
        await manager.broadcast(room_id, {
            "type": "BATTLE_START",
            "players": stats_info,
            "message": "Battle Started!"
        })
        print(f"✅ [BATTLE_DEBUG] 시작 신호 전송 성공!")

    except Exception as e:
        # 🚩 이 로그가 찍히면 범인을 바로 알 수 있습니다.
        import traceback
        print(f"🔥 [BATTLE_CRASH] start_battle_check 도중 치명적 에러 발생!")
        print(f"🔥 에러 내용: {e}")
        print(traceback.format_exc()) # 어디서 틀렸는지 상세 경로 출력

async def process_turn_redis(room_id: str):
    print(f"[Battle-Debug] process_turn_redis called for room {room_id}")
    room_data = await load_room_state(room_id)
    if not room_data: return
    
    players = room_data["players"]
    u1, u2 = players[0], players[1]
    su1, su2 = str(u1), str(u2)
    
    class StatObj:
        def __init__(self, d):
            for k, v in d.items(): setattr(self, k, v)
    
    stat1 = StatObj(room_data["character_stats"][su1])
    stat2 = StatObj(room_data["character_stats"][su2])
    
    state1 = BattleState.from_dict(room_data["battle_states"][su1])
    state2 = BattleState.from_dict(room_data["battle_states"][su2])
    
    print(f"[Battle-Debug] Loaded HP - U1: {state1.current_hp}/{state1.max_hp}, U2: {state2.current_hp}/{state2.max_hp}", flush=True)
    
    move1 = room_data["selections"][su1]
    move2 = room_data["selections"][su2]
    
    # 2. Logic (Turn Order)
    first = BattleManager.determine_turn_order(stat1, state1, move1, stat2, state2, move2)
    
    order = []
    if first == 1: order = [(u1, u2), (u2, u1)]
    else: order = [(u2, u1), (u1, u2)]
    
    turn_logs = []
    
    # [Debug] Initial HP
    print(f"[Battle-Debug] Turn Start - U1({u1}) HP: {state1.current_hp}, U2({u2}) HP: {state2.current_hp}")

    # 3. Execution Loop
    for att_id, def_id in order:
        s_att_id, s_def_id = str(att_id), str(def_id)
        
        att_stat = stat1 if att_id == u1 else stat2
        def_stat = stat2 if att_id == u1 else stat1
        
        att_state = state1 if att_id == u1 else state2
        def_state = state2 if att_id == u1 else state1
        
        move_id = move1 if att_id == u1 else move2
        
        # [New] Animation Trigger
        md = MOVE_DATA.get(move_id, {})
        turn_logs.append({
            "type": "turn_event",
            "event_type": "attack_start",
            "attacker": att_id,
            "defender": def_id,
            "move_id": move_id,
            "move_type": md.get("type", "normal")
        })

        # [Debug] Before Hit
        print(f"[Battle-Debug] Action - Attacker: {att_id}, Move: {move_id}, Def HP: {def_state.current_hp}")

        # Attack Logic 
        md = MOVE_DATA.get(move_id, {})
        
        # PP Check could go here, but omitted for brevity in auto-battle loop for now
        
        is_hit = False
        eff = md.get("effect", {})
        if isinstance(eff, dict) and eff.get("target") == "self": is_hit = True
        elif md.get("type") in ["heal", "buff"]: is_hit = True
        else:
             is_hit = BattleCalculator.check_hit(att_stat, att_state, def_stat, def_state, move_id)
        
        if not is_hit:
            turn_logs.append({
                "type": "turn_event",
                "event_type": "hit_result",
                "result": "miss",
                "attacker": att_id,
                "defender": def_id,
                "message": "공격이 빗나갔습니다!"
            })
        else:
             # Damage
             from app.game.game_assets import PET_TYPE_MAP
             def_pt = room_data["pet_types"][s_def_id]
             def_elem = PET_TYPE_MAP.get(def_pt, "normal")
             
             dmg, is_crit, eff_type = BattleManager.calculate_damage(att_stat, att_state, def_stat, def_state, move_id, defender_type=def_elem, field_data=room_data["field_effects"])
             
             def_state.current_hp = max(0, def_state.current_hp - dmg)
             
             # [Debug] After Hit
             print(f"[Battle-Debug] Hit! Dmg: {dmg}, Def Remaining: {def_state.current_hp}")
             
             turn_logs.append({
                 "type":"turn_event", "event_type":"hit_result", "result":"hit",
                 "attacker": att_id, "defender": def_id,
                 "damage": dmg, "defender_hp": def_state.current_hp, "is_critical": is_crit,
                 "message": f"{dmg} 피해!"
             })

             # Effects
             if def_state.current_hp > 0:
                elog = BattleManager.apply_move_effects(move_id, att_state, def_state, att_stat, f"User {att_id}", f"User {def_id}")
                for l in elog:
                    l["attacker"] = att_id
                    l["defender"] = def_id
                    if l.get("type") == "field_update":
                        room_data["field_effects"][l.get("field")] = l.get("value")
                    turn_logs.append(l)

        if def_state.current_hp <= 0: break

    # [New] Status Effect Damage
    for uid, state, stat in [(u1, state1, stat1), (u2, state2, stat2)]:
        if state.current_hp <= 0: continue 

        dmg, msg, detail = BattleManager.process_status_effects(stat, state)
        if dmg > 0:
            state.current_hp = max(0, state.current_hp - dmg)
            print(f"[Battle-Debug] Status Dmg - User: {uid}, Dmg: {dmg}, Rem: {state.current_hp}")
        
        if detail:
            detail["target"] = uid
            turn_logs.append(detail)
    
    # [Debug] Final State
    print(f"[Battle-Debug] Turn End - U1 HP: {state1.current_hp}, U2 HP: {state2.current_hp}")

    # [Debug] Final State
    print(f"[Battle-Debug] Turn End - U1 HP: {state1.current_hp}, U2 HP: {state2.current_hp}", flush=True)

    # 4. Serialize Back & Save
    d1 = state1.to_dict()
    d2 = state2.to_dict()
    print(f"[Battle-Debug] ToDict - U1: {d1['current_hp']}, U2: {d2['current_hp']}", flush=True)
    
    room_data["battle_states"][su1] = d1
    room_data["battle_states"][su2] = d2
    room_data["selections"] = {} 
    room_data["turn_count"] += 1
    
    await save_room_state(room_id, room_data)
    
    # 5. Broadcast Result
    player_states = {
        su1: {
            "hp": state1.current_hp, 
            "status": [state1.status_ailment] if state1.status_ailment else [],
            "pp": state1.pp 
        },
        su2: {
            "hp": state2.current_hp, 
            "status": [state2.status_ailment] if state2.status_ailment else [],
            "pp": state2.pp
        }
    }
    
    print(f"[Battle-Debug] Broadcast Payload: {player_states}")
    
    is_over = state1.current_hp <= 0 or state2.current_hp <= 0
    
    await manager.broadcast(room_id, {
        "type": "TURN_RESULT",
        "results": turn_logs,
        "player_states": player_states,
        "is_game_over": is_over
    })
    
    if is_over:
        winner, loser = None, None
        if state1.current_hp <= 0 and state2.current_hp <= 0:
            winner = "DRAW"
        elif state1.current_hp <= 0:
            winner, loser = u2, u1
        else:
            winner, loser = u1, u2
             
        if winner == "DRAW":
            draw_rewards = {}
            try:
                async with AsyncSessionLocal() as db:
                    draw_rewards = await char_service.process_battle_draw(db, u1, u2)
            except Exception as e:
                print(f"DB Error (Draw): {e}")

            await manager.broadcast(room_id, {
                "type": "GAME_OVER", 
                "result": "DRAW",
                "rewards": draw_rewards
            })
        else:
            reward_info = None
            try:
                async with AsyncSessionLocal() as db:
                        reward_info = await char_service.process_battle_result(db, winner, loser)
            except Exception as e:
                print(f"DB Update/Reward Error: {e}")
                    
            await manager.send_to_user(room_id, winner, {
                "type": "GAME_OVER",
                "result": "WIN",
                "winner": winner,
                "reward": reward_info
                })
                
            await manager.send_to_user(room_id, loser, {
                "type": "GAME_OVER",
                "result": "LOSE",
                "winner": winner
            })
        await delete_room_state(room_id)

    else:
        room_data["selections"] = {}
        room_data["turn_count"] += 1
        room_data["battle_states"][su1] = state1.to_dict()
        room_data["battle_states"][su2] = state2.to_dict()
        
        await save_room_state(room_id, room_data)