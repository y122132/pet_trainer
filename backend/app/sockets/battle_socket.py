
#backend/app/sockets/battle_socket.py
import json
import uuid
import random
from sqlalchemy import select
from app.services import char_service
from typing import Dict, Optional
from app.game.game_assets import MOVE_DATA
from app.game.matchmaker import matchmaker
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
        """ 방 ID별로 유저 ID와 웹소켓 객체를 매핑: {room_id: {user_id: WebSocket}}"""
        self.active_connections: Dict[str, Dict[int, WebSocket]] = {}

    async def connect(self, room_id: str, user_id: int, websocket: WebSocket):
        """새로운 웹소켓 연결을 관리 목록에 추가"""
        if room_id not in self.active_connections:
            self.active_connections[room_id] = {} # 방 없으면 생성
        self.active_connections[room_id][user_id] = websocket # 유저 소켓 저장

    def disconnect(self, room_id: str, user_id: int):
        """연결 종료 시 목록에서 삭제"""
        if room_id in self.active_connections: # 방이 있으면
            if user_id in self.active_connections[room_id]:
                del self.active_connections[room_id][user_id] # 유저 소켓 삭제
            if not self.active_connections[room_id]: # 방에 유저 없으면
                del self.active_connections[room_id] # 방 삭제

    async def broadcast(self, room_id: str, message: dict):
        """해당 방에 있는 모든 유저에게 메시지 전송"""
        if room_id in self.active_connections:
            """실시간으로 목록이 변할 수 있으므로 list로 복사해서 순회"""
            targets = list(self.active_connections[room_id].items())
            for uid, ws in targets:
                try:
                    if ws.client_state.value == 1: # 소켓 연결된 상태(1)에서만 json 전송
                        await ws.send_json(message)
                except:
                    self.disconnect(room_id, uid) # 오류 시 강제 연결 해제

    async def send_to_user(self, room_id: str, user_id: int, message: dict):
        """방 내부의 특정 유저 한 명에게만 메시지 전송"""
        ws = self.active_connections.get(room_id, {}).get(user_id)
        if ws:
            await ws.send_json(message)

manager = BattleConnectionManager()

# --- 매치메이킹(대기열) 엔드포인트 ---
@router.websocket("/ws/battle/matchmaking/{user_id}")
async def matchmaking_endpoint(websocket: WebSocket, user_id: int, token: str | None = None):
    try:
        await verify_websocket_token(websocket, token)
        await websocket.accept()

        async with AsyncSessionLocal() as db:
            """캐릭터 존재 여부 확인"""
            char_res = await db.execute(select(Character).where(Character.user_id == user_id))
            char = char_res.scalar_one_or_none()
            if not char:
                await websocket.close(code=4004)
                return
            
            """레벨 제한 확인"""
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
                        data = await websocket.receive_text() # 유저가 '나가기' 버튼을 누를 때까지 대기
                        if data == "EXIT": 
                            break
                except WebSocketDisconnect:
                    pass
                return
        """매치메이킹 대기열에 추가"""
        await matchmaker.add_to_queue(user_id, websocket)

        """대기열 상태 모니터링 및 매치 성사 대기"""
        while True:
            data = await websocket.receive_text()
            if data == "CANCEL": break
            if data == "AI_BATTLE":
                room_id = str(uuid.uuid4())
                await save_room_state(room_id, create_initial_room_data(room_id, is_ai_battle=True))
                await websocket.send_json({"type": "MATCH_FOUND", "room_id": room_id, "opponent_id": 0})
                break
    except WebSocketDisconnect:
        pass
    finally:
        matchmaker.remove_from_queue(user_id)

async def save_room_state(room_id: str, data: dict):
    redis = RedisManager.get_client()
    await redis.set(f"room:{room_id}", json.dumps(data), ex=3600)

async def load_room_state(room_id: str) -> Optional[dict]:
    redis = RedisManager.get_client()
    data = await redis.get(f"room:{room_id}")
    return json.loads(data) if data else None

async def handle_forfeit(room_id: str, leaver_id: int):
    """유저가 나갔을 때(기권) 남은 유저 승리 처리"""
    room_data = await load_room_state(room_id)
    if not room_data: return

    # 남은 유저 찾기
    winner_id = None
    for p_id in room_data["players"]:
        if p_id != leaver_id:
            winner_id = p_id
            break

    if winner_id is not None and winner_id != 0: # 0은 봇
        await manager.send_to_user(room_id, winner_id, {
            "type": "GAME_OVER",
            "result": "WIN",
            "reason": "opponent_fled",
            "message": "상대방이 대전을 포기했습니다."
        })
        # 기권 승 보상 지급 (평소보다 적게 혹은 적절히)
        async with AsyncSessionLocal() as db:
            await char_service.process_battle_result(db, winner_id, leaver_id)

async def delete_room_state(room_id: str):
    redis = RedisManager.get_client()
    await redis.delete(f"room:{room_id}:players_list")

def create_initial_room_data(room_id: str, is_ai_battle: bool = False) -> dict:
    """방 초기 상태 데이터를 생성합니다."""
    return {
        "room_id": room_id,
        "players": [],          # [user_id1, user_id2]
        "ready_status": {},     # user_id -> bool
        "character_stats": {},  # user_id -> dict (serialized Stat)
        "pet_types": {},        # user_id -> str
        "learned_skills": {},   # user_id -> list
        "battle_states": {},    # user_id -> dict (serialized BattleState)
        "selections": {},       # user_id -> move_id
        "turn_count": 0,
        "field_effects": {"weather": "clear", "location": "stadium"},
        "is_ai_battle": is_ai_battle
    }
# --- Endpoints ---
@router.websocket("/ws/battle/{room_id}/{user_id}")
async def battle_endpoint(websocket: WebSocket, room_id: str, user_id: int, token: str | None = None):
    try:
        await verify_websocket_token(websocket, token)
        await websocket.accept()
        await manager.connect(room_id, user_id, websocket)

        redis = RedisManager.get_client()
        players_set_key = f"room:{room_id}:players_list"

        # 유저 ID를 Set에 추가,SADD는 Redis 내부에서 순차적처리 덮어쓰기가 발생하지 않음
        await redis.sadd(players_set_key, user_id)
        # 현재 접속 확정된 인원수 확인
        player_count = await redis.scard(players_set_key)

        room_data = await load_room_state(room_id) or create_initial_room_data(room_id)
        
        # 유저 정보 로드 및 초기화
        async with AsyncSessionLocal() as db:
            char = (await db.execute(select(Character).where(Character.user_id == user_id))).scalar_one_or_none()
            stat = (await db.execute(select(Stat).where(Stat.character_id == char.id))).scalar_one_or_none()
            
            # JSON 내의 players 리스트도 동기화 (Set의 인원수를 기준으로 보정)
            current_players_in_set = await redis.smembers(players_set_key)
            room_data["players"] = [int(p) for p in current_players_in_set]
            
            # 유저별 상세 스탯 업데이트
            room_data["character_stats"][str(user_id)] = {
                k: v for k, v in stat.__dict__.items() 
                if not k.startswith('_')  # SQLAlchemy 내부 필드 제외
                and isinstance(v, (int, float, str, bool, list, dict)) # JSON 변환 가능 타입만 포함
            }
            room_data["pet_types"][str(user_id)] = char.pet_type
            room_data["learned_skills"][str(user_id)] = char.learned_skills or [1]
            if str(user_id) not in room_data["battle_states"]:
                room_data["battle_states"][str(user_id)] = BattleState(max_hp=stat.health, current_hp=stat.health).to_dict()

        # 업데이트된 전체 방 상태 저장
        await save_room_state(room_id, room_data)
        await manager.broadcast(room_id, {"type": "JOIN", "user_id": user_id, "message": f"User {user_id} joined."})

        # 덮어쓰기 위험이 없는 player_count 변수로 배틀 시작 판단
        if player_count == 2:
            await start_battle_check(room_id)

        # AI 봇 설정
        if room_data.get("is_ai_battle") and 0 not in room_data["players"]:
            room_data["players"].append(0)
            room_data["character_stats"]["0"] = room_data["character_stats"][str(user_id)]
            room_data["pet_types"]["0"] = "bear"
            room_data["learned_skills"]["0"] = [5, 15, 30]
            room_data["battle_states"]["0"] = room_data["battle_states"][str(user_id)]

        await save_room_state(room_id, room_data)
        await manager.broadcast(room_id, {"type": "JOIN", "user_id": user_id, "message": f"User {user_id} joined."})

        if len(room_data["players"]) == 2:
            await start_battle_check(room_id)

        # 메인 루프
        while True:
            msg = await websocket.receive_json()
            if msg.get("action") == "select_move":
                move_id = msg.get("move_id")
                redis = RedisManager.get_client()
                
                # 유저 선택 저장
                await redis.hset(f"room:{room_id}:selections", str(user_id), move_id)

                room_data = await load_room_state(room_id)
                if room_data and room_data.get("is_ai_battle"):
                    # 봇(ID 0)의 스킬 리스트에서 하나를 랜덤으로 뽑음
                    bot_skills = room_data["learned_skills"].get("0", [1])
                    bot_move = random.choice(bot_skills) # 여기서 import random이 사용됨
                    
                    # 봇의 선택을 유저인 것처럼 Redis에 강제로 저장
                    await redis.hset(f"room:{room_id}:selections", "0", str(bot_move))
                    print(f"[Battle] AI selected move: {bot_move}")

                all_selections = await redis.hgetall(f"room:{room_id}:selections")
                if len(all_selections) == 2:
                    room_data = await load_room_state(room_id)
                    if room_data:
                        room_data["selections"] = {k: int(v) for k, v in all_selections.items()}
                        await save_room_state(room_id, room_data)
                        await redis.delete(f"room:{room_id}:selections")
                        await process_turn_redis(room_id)
                else:
                    await manager.send_to_user(room_id, user_id, {"type": "WAITING"})

    except WebSocketDisconnect:
        manager.disconnect(room_id, user_id)
        await handle_forfeit(room_id, user_id)
    except Exception as e:
        print(f"Error: {e}")
        await websocket.close(code=4000)
        
async def start_battle_check(room_id: str):
    room_data = await load_room_state(room_id)
    if not room_data: return
    
    stats_info = {}
    for uid in room_data["players"]:
        uid_str = str(uid)
        
        # 스킬 상세 정보
        sids = room_data["learned_skills"].get(uid_str, [])
        details = []
        for sid in sids:
             md = MOVE_DATA.get(sid)
             if md:
                 # [New] PP Info
                 max_pp = md.get("max_pp", 20)
                 current_pp = room_data["battle_states"][uid_str]["pp"].get(str(sid), max_pp)

                 details.append({
                     "id": sid, "name": md["name"], "type": md["type"],
                     "power": md["power"], "desc": md["description"],
                     "max_pp": max_pp, "pp": current_pp # [New]
                 })
        
        bs = room_data["battle_states"][uid_str]
        stats_info[uid_str] = {
            "hp": bs["current_hp"],
            "max_hp": bs["max_hp"],
            "name": f"User {uid_str}",
            "pet_type": room_data["pet_types"].get(uid_str, "dog"),
            "skills": details
        }
        
    await manager.broadcast(room_id, {
        "type": "BATTLE_START",
        "players": stats_info,
        "message": "Battle Started!"
    })

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
        await RedisManager.get_client().delete(f"room:{room_id}")

    else:
        room_data["selections"] = {}
        room_data["turn_count"] += 1
        room_data["battle_states"][su1] = state1.to_dict()
        room_data["battle_states"][su2] = state2.to_dict()
        
        await save_room_state(room_id, room_data)
