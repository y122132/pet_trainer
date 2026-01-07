from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from typing import Dict, List, Optional
import json
import asyncio
from app.game.battle_manager import BattleManager, BattleState
from app.game.battle_calculator import BattleCalculator
from app.game.game_assets import MOVE_DATA
from app.db.database import AsyncSessionLocal
from app.services import char_service
from sqlalchemy import select
from app.db.models.character import Character, Stat
from dataclasses import asdict
from app.core.security import verify_websocket_token
from app.db.database_redis import RedisManager

router = APIRouter()

# --- Matchmaking Endpoint ---
from app.game.matchmaker import matchmaker

@router.websocket("/ws/battle/matchmaking/{user_id}")
async def matchmaking_endpoint(websocket: WebSocket, user_id: int, token: str | None = None):
    # 1. 보안 검증
    try:
        await verify_websocket_token(websocket, token)
    except Exception as e:
        print(f"[Battle-Socket] Token verification failed: {e} (Token: {token})")
        return

    await websocket.accept()
    
    # 2. 레벨 제한 체크 (Lv.10 이상)
    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(select(Character).where(Character.user_id == user_id))
            character = result.scalar_one_or_none()
            
            if not character:
                await websocket.close(code=4004, reason="Character not found")
                return

            if character.level < 10:
                print(f"[Battle-Socket] User {user_id} rejected: Level {character.level} < 10")
                # [User Request] 10레벨 미만 안내 메시지 전송
                await websocket.send_json({
                    "type": "ERROR",
                    "code": "LEVEL_TOO_LOW",
                    "message": "10레벨 미만은 배틀 시스템을 이용할 수 없습니다."
                })
                # 메시지 전송 후 잠시 대기하지 않으면 클라이언트가 받기 전에 끊길 수 있음 (Optional, but safe)
                await asyncio.sleep(0.1) 
                await websocket.close(code=4003, reason="Level too low")
                return
    except Exception as e:
        print(f"[Battle-Socket] DB Level Check Error: {e}")
        await websocket.close(code=4000, reason="Server Error")
        return
    
    try:
        # 대기열 등록
        await matchmaker.add_to_queue(user_id, websocket)
        
        # 연결 유지 (매칭 대기)
        while True:
            # 클라이언트로부터 메시지 받을 일은 딱히 없으나, 연결 유지 확인용
            # 클라이언트가 취소 요청("CANCEL")을 보낼 수도 있음
            data = await websocket.receive_text()
            if data == "CANCEL":
                break
            elif data == "AI_BATTLE":
                # [New] AI 대전 요청 시 즉시 매칭 성사
                matchmaker.remove_from_queue(user_id)
                import uuid
                room_id = str(uuid.uuid4())
                # [Fix] Use helper to create FULL initial state
                initial_data = create_initial_room_data(room_id, is_ai_battle=True)
                await save_room_state(room_id, initial_data)
                
                await websocket.send_json({
                    "type": "MATCH_FOUND",
                    "room_id": room_id,
                    "opponent_id": 0 # 0 indicates AI/Bot
                })
                break
                
    except WebSocketDisconnect:
        pass
    finally:
        matchmaker.remove_from_queue(user_id)


# --- Connection Management (Local) ---
# 웹소켓 연결은 직렬화할 수 없으므로 여전히 서버 메모리에 유지해야 합니다.
# Key: room_id, Value: Dict[user_id, WebSocket]
local_connections: Dict[str, Dict[int, WebSocket]] = {}

def get_room_connections(room_id: str) -> Dict[int, WebSocket]:
    if room_id not in local_connections:
        local_connections[room_id] = {}
    return local_connections[room_id]

async def broadcast_to_room(room_id: str, message: dict):
    conns = get_room_connections(room_id)
    # [Scalability Note] 다중 인스턴스 환경라면 여기서 Redis Pub/Sub을 발행해야 함.
    # 현재는 Redis State Persistence에 집중하므로, 동일 서버에 접속한 유저에게만 전송.
    for ws in conns.values():
        try:
            await ws.send_json(message)
        except:
            pass # Disconnected logic handled elsewhere

async def send_to_user(room_id: str, user_id: int, message: dict):
    conns = get_room_connections(room_id)
    if user_id in conns:
        try:
            await conns[user_id].send_json(message)
        except:
            pass

# --- Redis State Helpers ---

async def save_room_state(room_id: str, data: dict):
    """
    방의 상태(JSON)를 Redis에 저장합니다.
    """
    redis = RedisManager.get_client()
    try:
        # Pydantic or Custom Serialization
        await redis.set(f"room:{room_id}", json.dumps(data), ex=3600) # 1시간 TTL
    finally:
        # pool.disconnect() is handled by RedisManager.close() on shutdown
        pass

async def load_room_state(room_id: str) -> Optional[dict]:
    """
    Redis에서 방 상태를 불러옵니다.
    """
    redis = RedisManager.get_client()
    data = await redis.get(f"room:{room_id}")
    # redis-py's close is safe on pools
    # await redis.close() 
    if data:
        return json.loads(data)
    return None

async def delete_room_state(room_id: str):
    redis = RedisManager.get_client()
    await redis.delete(f"room:{room_id}")

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

# --- Logic Wrappers ---

# --- Logic Wrappers ---

# Helpers removed; using BattleState methods directly.


# --- Endpoints ---

@router.websocket("/ws/battle/{room_id}/{user_id}")
async def battle_endpoint(websocket: WebSocket, room_id: str, user_id: int, token: str | None = None):
    # 1. 보안 검증
    try:
        await verify_websocket_token(websocket, token)
    except Exception as e:
        print(f"Token verification failed: {e}")
        return

    # 2. 로컬 연결 관리
    await websocket.accept()
    
    conns = get_room_connections(room_id)
    conns[user_id] = websocket
    
    # 3. Redis 상태 로드 및 초기화
    room_data = await load_room_state(room_id)
    
    # 방이 없으면 파라미터 초기화
    if not room_data:
        room_data = create_initial_room_data(room_id)
    
    # [Robustness] Ensure all keys exist (in case of partial initialization)
    default_data = create_initial_room_data(room_id)
    for k, v in default_data.items():
        if k not in room_data:
            room_data[k] = v

    # AI 배틀 여부 확인
    from app.game.matchmaker import matchmaker
    # 룸 데이터가 새로 생성된 경우에만 체크 (또는 URL 파라미터 등으로도 가능하지만 여기선 로직상 첫 진입 유저 기준)
    # 실제로는 클라이언트가 MATCH_FOUND의 opponent_id가 0임을 알고도 여기 접속함.

    # 플레이어 등록
    if user_id not in room_data["players"]:
        if len(room_data["players"]) >= 2:
            await websocket.close(code=4003, reason="Room is full")
            del conns[user_id]
            return
        room_data["players"].append(user_id)

    # [New] AI 대전인 경우 봇 추가 (Bot ID: 0)
    # 클라이언트가 처음 접속할 때 결정
    if str(user_id) not in room_data["character_stats"] and len(room_data["players"]) == 1:
        # 이 유저가 처음 들어온 건데, 상대가 봇인지 확인하는 간단한 방법? 
        # 일단 MATCH_FOUND에서 보낸 정보를 기억하거나, 특정 유저 ID(0)를 플레이어 리스트에 넣음.
        pass
    
    # DB에서 캐릭터 가져오기
    try:
        async with AsyncSessionLocal() as db:
            stmt = select(Character).where(Character.user_id == user_id)
            result = await db.execute(stmt)
            character_obj = result.scalar_one_or_none()
            
            if character_obj:
                # Stat
                stmt_stat = select(Stat).where(Stat.character_id == character_obj.id)
                res_stat = await db.execute(stmt_stat)
                stat_obj = res_stat.scalar_one_or_none()
                
                if stat_obj:
                    # Serialize Stat
                    room_data["character_stats"][str(user_id)] = {
                        "strength": stat_obj.strength,
                        "defense": stat_obj.defense,
                        "agility": stat_obj.agility,
                        "intelligence": stat_obj.intelligence,
                        "luck": stat_obj.luck,
                        "health": stat_obj.health
                    }
                    room_data["pet_types"][str(user_id)] = character_obj.pet_type
                    room_data["learned_skills"][str(user_id)] = character_obj.learned_skills or [1]
                    
                    # BattleState Init (if not exists)
                    if str(user_id) not in room_data["battle_states"]:
                        initial_bs = BattleState(max_hp=stat_obj.health, current_hp=stat_obj.health)
                        room_data["battle_states"][str(user_id)] = initial_bs.to_dict()
                else:
                    await websocket.close(code=4004, reason="No stat found")
                    del conns[user_id]
                    return
            else:
                 await websocket.close(code=4004, reason="No character found")
                 del conns[user_id]
                 return
    except Exception as e:
        print(f"DB Error: {e}")
        await websocket.close(code=4004, reason="DB Error")
        del conns[user_id]
        return

    # [New] AI Battle: Add Bot to the room if not already there
    if room_data.get("is_ai_battle") and 0 not in room_data["players"]:
        room_data["players"].append(0)
        # Init Bot Stats (Clone user's for a fair fight, but can be customized)
        user_stats = room_data["character_stats"][str(user_id)]
        room_data["character_stats"]["0"] = dict(user_stats)
        room_data["pet_types"]["0"] = "bear" # Bot is a bear!
        room_data["learned_skills"]["0"] = [5, 10, 15, 25, 30, 50] # Some skills
        room_data["battle_states"]["0"] = BattleState(max_hp=user_stats["health"], current_hp=user_stats["health"]).to_dict()

    # Redis 저장
    await save_room_state(room_id, room_data)

    # 접속 알림
    await broadcast_to_room(room_id, {
        "type": "JOIN",
        "user_id": user_id,
        "current_players": len(room_data["players"]),
        "message": f"User {user_id} joined the battle."
    })
    
    # 풀방 체크 & 배틀 시작
    if len(room_data["players"]) == 2:
        await start_battle_check(room_id)

    # --- 메인 루프 ---
    try:
        while True:
            msg = await websocket.receive_json()
            
            # [Fix] 상태 최신화 (다른 유저에 의해 변경되었을 수 있으므로 매번 로드)
            room_data = await load_room_state(room_id)
            if not room_data: break
            
            if msg.get("action") == "select_move":
                move_id = msg.get("move_id")
                
                # [Debug] Trace
                print(f"[Battle-Debug] User {user_id} selecting Move {move_id}")
                
                # 검증
                known_skills = room_data["learned_skills"].get(str(user_id), [])
                
                # [New] Struggle Check (PP Check)
                bs_dict = room_data["battle_states"].get(str(user_id))
                if bs_dict is None:
                    print(f"[Battle-Socket-Crash] Critical: User {user_id} has no battle state in room {room_id}")
                    await send_to_user(room_id, user_id, {"type": "ERROR", "message": "State Error: Rejoin recommended"})
                    continue
                    
                bs_obj = BattleState.from_dict(bs_dict)
                
                all_pp_zero = True
                for skid in known_skills:
                    if bs_obj.pp.get(str(skid), 99) > 0: # Default non-zero if missing for now
                        all_pp_zero = False
                        break
                
                if all_pp_zero:
                    move_id = 0 # Force Struggle
                
                if move_id != 0 and move_id not in known_skills:
                   print(f"[Battle-Debug] Invalid Skill: {move_id} not in {known_skills}")
                   await send_to_user(room_id, user_id, {"type": "ERROR", "message": "Invalid Skill"})
                   continue
                
                # 행동 불가 체크 (process_turn_redis 확인)
                # bs_obj already loaded check above
                pass
                
                # 선택 저장
                room_data["selections"][str(user_id)] = move_id
                
                # [New] AI Battle Selection
                if room_data.get("is_ai_battle"):
                    import random
                    bot_skills = room_data["learned_skills"].get("0", [5])
                    room_data["selections"]["0"] = random.choice(bot_skills)
                    print(f"[Battle-AI] Bot selected Move {room_data['selections']['0']}")

                await save_room_state(room_id, room_data)
                
                await send_to_user(room_id, user_id, {"type": "WAITING", "message": "Waiting..."})
                
                # 턴 진행 체크
                print(f"[Battle-Debug] Room {room_id} Selections: {len(room_data['selections'])}/2")
                if len(room_data["selections"]) == 2:
                    await process_turn_redis(room_id)
                elif len(room_data["selections"]) > 2:
                    print(f"[Battle-Debug] Error: Too many selections {room_data['selections']}")
                    room_data["selections"] = {} # Reset safety
                    await save_room_state(room_id, room_data)

    except WebSocketDisconnect:
        conns = get_room_connections(room_id)
        if user_id in conns: del conns[user_id]
        await broadcast_to_room(room_id, {"type": "LEAVE", "user_id": user_id})
    except Exception as e:
        import traceback
        print(f"[Battle-Socket-Crash] Unhandled Exception: {e}")
        traceback.print_exc()
        # Close with error code
        await websocket.close(code=4000, reason=f"Server Error: {str(e)}")
        conns = get_room_connections(room_id)
        if user_id in conns: del conns[user_id]
        
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
        
    await broadcast_to_room(room_id, {
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
    
    # 1. Deserialize
    # Stat은 계산 시 Object 형태가 필요할 수 있음 (BattleCalculator가 속성 접근을 .strength로 하는지 dict[]로 하는지 확인 필요)
    # 기존 코드: stat.strength -> Object Access
    # 따라서 Mock Object 또는 DictToObj 변환 필요.
    # 간단히 namedtuple이나 class로 변환
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
             turn_logs.append({"type":"turn_event", "result":"miss", "message":"빗나감!"})
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
    
    await broadcast_to_room(room_id, {
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
             # [New] 무승부 보상 로직 호출
             draw_rewards = {}
             try:
                 async with AsyncSessionLocal() as db:
                     draw_rewards = await char_service.process_battle_draw(db, u1, u2)
             except Exception as e:
                 print(f"DB Error (Draw): {e}")

             await broadcast_to_room(room_id, {
                 "type": "GAME_OVER", 
                 "result": "DRAW",
                 "rewards": draw_rewards # 클라이언트에서 이 정보를 보여줘야 함
             })
        else:
             # [Fix] 배틀 종료 시 체력 스탯 덮어쓰기 로직 제거
             reward_info = None
             try:
                 async with AsyncSessionLocal() as db:
                      reward_info = await char_service.process_battle_result(db, winner, loser)
             except Exception as e:
                 print(f"DB Update/Reward Error: {e}")
                 
             await send_to_user(room_id, winner, {
                 "type": "GAME_OVER",
                 "result": "WIN",
                 "winner": winner,
                 "reward": reward_info
             })
             
             await send_to_user(room_id, loser, {
                 "type": "GAME_OVER",
                 "result": "LOSE",
                 "winner": winner
             })
        # Cleanup
        await delete_room_state(room_id)
