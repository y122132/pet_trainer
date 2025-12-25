from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from typing import Dict, List
import json
import asyncio
from app.game.battle_manager import BattleManager, BattleState
from app.game.battle_calculator import BattleCalculator
from app.game.game_assets import MOVE_DATA
from app.db.database import AsyncSessionLocal
from app.services import char_service
from sqlalchemy import select
from app.db.models.character import Character, Stat
from dataclasses import dataclass

router = APIRouter()

# --- Room Management ---
class BattleRoom:
    def __init__(self, room_id: str):
        self.room_id = room_id
        self.connections: Dict[int, WebSocket] = {} # user_id -> websocket
        self.ready_status: Dict[int, bool] = {}
        self.character_stats: Dict[int, Stat] = {} # user_id -> Stat Object
        self.pet_types: Dict[int, str] = {} # user_id -> pet_type
        self.learned_skills: Dict[int, List[int]] = {} # user_id -> learned_skills
        self.battle_states: Dict[int, BattleState] = {} # user_id -> BattleState
        self.selections: Dict[int, int] = {} # user_id -> move_id
        self.turn_count = 0

    async def connect(self, websocket: WebSocket, user_id: int):
        await websocket.accept()
        self.connections[user_id] = websocket
        self.ready_status[user_id] = False 
        self.connections[user_id] = websocket
        self.ready_status[user_id] = False 
        # self.battle_states[user_id] = BattleState() -> Will be initialized with HP later

    
    def disconnect(self, user_id: int):
        if user_id in self.connections:
            del self.connections[user_id]
        if user_id in self.selections:
            del self.selections[user_id]
        if user_id in self.battle_states:
            del self.battle_states[user_id]
        if user_id in self.pet_types:
            del self.pet_types[user_id]
        if user_id in self.learned_skills:
            del self.learned_skills[user_id]
            
    async def broadcast(self, message: dict):
        for connection in self.connections.values():
            await connection.send_json(message)

    async def send_to(self, user_id: int, message: dict):
        if user_id in self.connections:
            await self.connections[user_id].send_json(message)

    def is_full(self):
        return len(self.connections) >= 2

    def all_selected(self):
        return len(self.selections) == 2 and len(self.connections) == 2

    def reset_selections(self):
        self.selections = {}

# Global Room Store (In-memory)
rooms: Dict[str, BattleRoom] = {}

@router.websocket("/ws/battle/{room_id}/{user_id}")
async def battle_endpoint(websocket: WebSocket, room_id: str, user_id: int):
    # 1. Room 생성 또는 조회
    if room_id not in rooms:
        rooms[room_id] = BattleRoom(room_id)
    
    room = rooms[room_id]
    
    if room.is_full() and user_id not in room.connections:
        await websocket.close(code=4003, reason="Room is full")
        return

    # 2. 연결 및 캐릭터 데이터 로드
    await room.connect(websocket, user_id)
    
    # DB에서 캐릭터 스탯 가져오기
    try:
        async with AsyncSessionLocal() as db:
            stmt = select(Character).where(Character.user_id == user_id)
            result = await db.execute(stmt)
            character_obj = result.scalar_one_or_none()
            
            if character_obj:
                stmt_stat = select(Stat).where(Stat.character_id == character_obj.id)
                res_stat = await db.execute(stmt_stat)
                stat_obj = res_stat.scalar_one_or_none()
                
                if stat_obj:
                    # Store a snapshot (or reference if safe)
                    room.character_stats[user_id] = stat_obj
                    room.pet_types[user_id] = character_obj.pet_type
                    
                    # Initialize BattleState with current HP from DB
                    room.battle_states[user_id] = BattleState(max_hp=stat_obj.health, current_hp=stat_obj.health)
                    
                    # [Fix] 기존 데이터 호환성을 위해 스킬이 없으면 기본 스킬(1: 짖기) 부여
                    room.learned_skills[user_id] = character_obj.learned_skills if character_obj.learned_skills else [1]
                else:
                    await websocket.close(code=4004, reason="No character stat found")
                    return
            else:
                 await websocket.close(code=4004, reason="No character found")
                 return
    except Exception as e:
        print(f"Error loading character: {e}")
        await websocket.close(code=4004, reason="DB Error")
        return

    # 3. 접속 알림
    await room.broadcast({
        "type": "JOIN",
        "user_id": user_id,
        "current_players": len(room.connections),
        "message": f"User {user_id} joined the battle."
    })
    
    # 4. 양쪽 다 접속했으면 배틀 시작 알림
    if room.is_full():
        # 양측 스탯 정보 및 스킬 정보 교환
        stats_info = {}
        
        for uid, stat in room.character_stats.items():
            # 스킬 ID 리스트를 상세 정보 리스트로 변환
            skill_ids = room.learned_skills.get(uid, [])
            skill_details = []
            for sid in skill_ids:
                s_data = MOVE_DATA.get(sid)
                if s_data:
                    skill_details.append({
                        "id": sid,
                        "name": s_data["name"],
                        "type": s_data["type"],
                        "power": s_data["power"],
                        "desc": s_data["description"]
                    })
            
            battle_state = room.battle_states[uid]
            
            # [Fix] 스탯 랭크 초기화 (재경기 시 이전 버프 초기화)
            room.battle_states[uid].stages = {
                "strength": 0, "defense": 0, "agility": 0, 
                "intelligence": 0, "accuracy": 0, "evasion": 0
            }

            stats_info[uid] = {
                "hp": battle_state.current_hp,
                "max_hp": battle_state.max_hp, 
                "name": f"User {uid}",
                "pet_type": room.pet_types.get(uid, "dog"),
                "skills": skill_details # [New] 상세 스킬 정보 전송
            }
            
        await room.broadcast({
            "type": "BATTLE_START",
            "players": stats_info,
            "message": "Battle Started!"
        })

    try:
        while True:
            data = await websocket.receive_json()
            # Expecting: {"action": "select_move", "move_id": 1}
            
            if data.get("action") == "select_move":
                move_id = data.get("move_id")

                # [New] 스킬 보유 검증
                known_skills = room.learned_skills.get(user_id, [])
                if move_id not in known_skills:
                    await room.send_to(user_id, {
                        "type": "ERROR", 
                        "message": "Invalid Move! You haven't learned this skill."
                    })
                    continue
                
                # 행동 불가 체크 (마비, 잠듦 등)
                can_move, fail_msg = BattleManager.can_move(room.battle_states[user_id])
                
                room.selections[user_id] = move_id
                
                # 본인에게는 "대기 중"
                await room.send_to(user_id, {
                    "type": "WAITING", 
                    "message": "Waiting for opponent..."
                })
                
                # 상대방에게 "상대가 고르는 중..." 알림
                for other_id in room.connections:
                    if other_id != user_id:
                        await room.send_to(other_id, {
                            "type": "OPPONENT_SELECTING",
                            "message": "Opponent is selecting a move..."
                        })
                
                # 양측 모두 선택 완료 시 턴 진행
                if room.all_selected():
                    await process_turn(room)
                    
    except WebSocketDisconnect:
        room.disconnect(user_id)
        await room.broadcast({
            "type": "LEAVE",
            "user_id": user_id,
            "message": "Opponent disconnected."
        })
        if len(room.connections) == 0:
            del rooms[room_id]

async def process_turn(room: BattleRoom):
    try:
        user_ids = list(room.connections.keys())
        u1 = user_ids[0]
        u2 = user_ids[1]
        
        stat1 = room.character_stats[u1]
        stat2 = room.character_stats[u2]
        
        state1 = room.battle_states[u1]
        state2 = room.battle_states[u2]
        
        move1 = room.selections[u1]
        move2 = room.selections[u2]
        
        # 1. 선공 결정
        first = BattleManager.determine_turn_order(stat1, state1, move1, stat2, state2, move2)
        
        attacker_order = []
        if first == 1:
            attacker_order = [(u1, u2), (u2, u1)]
        else:
            attacker_order = [(u2, u1), (u1, u2)]
            
        turn_logs = []
        
        # 2. 턴 진행 (순차적 리스트 생성)
        for attacker_id, defender_id in attacker_order:
            attacker_stat = room.character_stats[attacker_id]
            defender_stat = room.character_stats[defender_id]
            
            attacker_state = room.battle_states[attacker_id]
            defender_state = room.battle_states[defender_id]
            
            move_id = room.selections[attacker_id]
            
            if attacker_state.current_hp <= 0: continue

            # 행동 불가 체크 (Immobile)
            can_move, fail_msg = BattleManager.can_move(attacker_state)
            if not can_move:
                turn_logs.append({
                    "type": "turn_event",
                    "event_type": "immobile",
                    "attacker": attacker_id,
                    "message": fail_msg
                })
                continue

            # 1. 공격 선언 (Start)
            turn_logs.append({
                "type": "turn_event",
                "event_type": "attack_start",
                "attacker": attacker_id,
                "move_id": move_id,
                "message": f"{move_id}번 기술 시전!"
            })
            
            # 2. 명중 체크 (Hit Check)
            is_hit = BattleCalculator.check_hit(attacker_stat, attacker_state, defender_stat, defender_state, move_id)
            
            if not is_hit:
                # 빗나감
                turn_logs.append({
                    "type": "turn_event",
                    "event_type": "hit_result",
                    "result": "miss",
                    "attacker": attacker_id,
                    "defender": defender_id,
                    "message": "공격이 빗나갔습니다!"
                })
            else:
                # [New] 방어자 속성 조회
                from app.game.game_assets import PET_TYPE_MAP
                def_pet_type = room.pet_types.get(defender_id, "dog")
                def_elemental_type = PET_TYPE_MAP.get(def_pet_type, "normal")

                # 적중 -> 데미지 계산
                # [Fix] defender_type 전달 및 effectiveness 수신
                damage, is_critical, effectiveness = BattleManager.calculate_damage(
                    attacker_stat, attacker_state, defender_stat, defender_state, move_id, defender_type=def_elemental_type
                )
                
                # HP 적용
                defender_state.current_hp -= damage
                if defender_state.current_hp < 0: defender_state.current_hp = 0
                
                # 메시지 구성
                hit_msg = "명중!"
                if is_critical: hit_msg = "크리티컬 히트!"
                if effectiveness == "super": hit_msg += " (효과가 굉장했다!)"
                elif effectiveness == "not_very": hit_msg += " (효과가 별로인 듯하다...)"

                turn_logs.append({
                    "type": "turn_event",
                    "event_type": "hit_result",
                    "result": "hit",
                    "attacker": attacker_id,
                    "defender": defender_id,
                    "damage": damage,
                    "is_critical": is_critical,
                    "effectiveness": effectiveness, # 클라이언트 연출용
                    "defender_hp": defender_state.current_hp,
                    "message": hit_msg
                })

                if damage > 0:
                     turn_logs.append({
                        "type": "turn_event",
                        "event_type": "damage_apply",
                        "target": defender_id,
                        "damage": damage,
                        "target_hp": defender_state.current_hp,
                        "message": f"{damage}의 데미지를 입었습니다!"
                    })

                # 3. 부가 효과 적용 (Effects)
                if defender_state.current_hp > 0:
                    effect_logs = BattleManager.apply_move_effects(move_id, attacker_state, defender_state, attacker_stat)
                    for eff in effect_logs:
                        eff["event_type"] = "effect_apply" # 클라이언트 식별용
                        eff["type"] = "turn_event" # turn_event 타입 유지
                        turn_logs.append(eff)
            
            if defender_state.current_hp <= 0: break 
        
        # 3. 턴 종료 시 상태 이상 데미지 처리
        for uid in user_ids:
            # stat = room.character_stats[uid] -> Not used for HP anymore
            state = room.battle_states[uid]
            
            if state.current_hp > 0:
                dmg, msg, detail = BattleManager.process_status_effects(None, state) # stat param removed/unused in manager logic
                if dmg > 0 or msg:
                    state.current_hp -= dmg
                    if state.current_hp < 0: state.current_hp = 0
                    
                    log_data = {
                         "type": "turn_event",
                         "event_type": "status_damage" if dmg > 0 else "status_recover",
                         "target": uid,
                         "damage": dmg,
                         "message": msg,
                         "target_hp": state.current_hp
                    }
                    if detail:
                        log_data.update(detail)
                        
                    turn_logs.append(log_data)
        
        # 4. 결과 전송 (순차적 재생 가능하도록 리스트로 전송)
        await room.broadcast({
            "type": "TURN_RESULT",
            "results": turn_logs,
            "turn": room.turn_count
        })
        
        room.turn_count += 1
        room.reset_selections()
        
        # 5. 게임 종료 체크
        winner = None
        loser = None
        if room.battle_states[u1].current_hp <= 0:
            winner = u2
            loser = u1
        elif room.battle_states[u2].current_hp <= 0:
            winner = u1
            loser = u2
            
        if winner is not None:
            # [Fix] 배틀 종료 시 체력 스탯 덮어쓰기 로직 제거 (Stat Loss Bug Fix)
            # 이제 승리 보상만 처리하고, health 스탯은 건드리지 않음
            reward_info = None
            try:
                async with AsyncSessionLocal() as db:
                     # 보상 처리
                     reward_info = await char_service.process_battle_result(db, winner, loser)
            except Exception as e:
                print(f"DB Update/Reward Error: {e}")
                
            # [Fix] 승자와 패자에게 다른 메시지 전송
            # 승자에게: Victory + Reward
            await room.send_to(winner, {
                "type": "GAME_OVER",
                "result": "WIN",
                "winner": winner,
                "reward": reward_info
            })
            
            # 패자에게: Defeat (보상 없음)
            await room.send_to(loser, {
                "type": "GAME_OVER",
                "result": "LOSE",
                "winner": winner
            })
            
            # [Refinement] 배틀 종료 시 스탯 랭크 초기화 (메모리 상태 정리)
            for uid in [u1, u2]:
                if uid in room.battle_states:
                    room.battle_states[uid].stages = {
                        "strength": 0, "defense": 0, "agility": 0, 
                        "intelligence": 0, "accuracy": 0, "evasion": 0
                    }
             
    except Exception as e:
        print(f"Turn Processing Error: {e}")
        await room.broadcast({"type": "ERROR", "message": str(e)})
