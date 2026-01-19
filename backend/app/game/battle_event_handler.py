from app.repositories.battle_repository import BattleRoomRepository
from app.game.battle_manager import BattleManager, BattleState
from app.game.game_assets import MOVE_DATA
from app.db.database import AsyncSessionLocal
from app.services import char_service
import random
import traceback

class BattleEventHandler:
    """
    배틀 소켓 메시지 처리 및 로직 분기
    """
    
    def __init__(self, manager, room_id: str):
        self.manager = manager # ConnectionManager
        self.room_id = room_id

    async def handle_select_move(self, user_id: int, move_id: int):
        """
        스킬 선택 처리 및 턴 실행 검사
        """
        room_data = await BattleRoomRepository.load_room(self.room_id)
        if not room_data: return

        # 1. 내 선택 저장
        await BattleRoomRepository.submit_move(self.room_id, user_id, move_id)
        
        # 2. AI 배틀일 경우 봇 선택 자동 수행
        if room_data.get("is_ai_battle"):
            # 봇이 사용 가능한 스킬 중 랜덤 선택 (또는 AI 로직)
            bot_skills = room_data["learned_skills"].get("0", [5])
            bot_move = random.choice(bot_skills)
            await BattleRoomRepository.submit_move(self.room_id, 0, bot_move)

        # 3. 모든 플레이어가 선택했는지 확인
        all_selections = await BattleRoomRepository.get_all_selections(self.room_id)
        
        # 4. 턴 처리 실행 (2명 이상 선택 시)
        # Note: 실제 플레이어 수와 일치해야 하지만 1:1 기준 2명
        if len(all_selections) >= 2:
            # [CRITICAL] Race Condition 방지를 위한 Lock
            if await BattleRoomRepository.acquire_lock(self.room_id):
                try:
                    await self._execute_turn(all_selections)
                finally:
                    await BattleRoomRepository.release_lock(self.room_id)
            else:
                # 이미 다른 요청(상대방)에 의해 턴이 처리 중임 -> 무시
                pass
        else:
            # 상대방을 기다림
            await self.manager.send_to_user(self.room_id, user_id, {"type": "WAITING"})

    async def handle_surrender(self, user_id: int):
        """기권 처리"""
        await self._process_game_over(loser_id=user_id, reason="surrender")

    async def _execute_turn(self, selections: dict):
        """
        실제 턴 계산 로직 (BattleManager 호출)
        """
        room_data = await BattleRoomRepository.load_room(self.room_id)
        if not room_data: return

        room_data["selections"] = selections
        await self._process_turn_core(room_data)

    async def _process_turn_core(self, room_data: dict):
        # 1. Setup Data
        players = room_data["players"]
        if len(players) < 2: return 
        
        u1, u2 = players[0], players[1]
        su1, su2 = str(u1), str(u2)
        
        # Helper Class for Stat
        class StatObj:
            def __init__(self, d):
                for k, v in d.items(): setattr(self, k, v)
        
        stat1 = StatObj(room_data["character_stats"][su1])
        stat2 = StatObj(room_data["character_stats"][su2])
        
        state1 = BattleState.from_dict(room_data["battle_states"][su1])
        state2 = BattleState.from_dict(room_data["battle_states"][su2])
        
        move1 = room_data["selections"][su1]
        move2 = room_data["selections"][su2]
        
        # 2. Logic (Turn Order)
        first = BattleManager.determine_turn_order(stat1, state1, move1, stat2, state2, move2)
        order = [(u1, u2), (u2, u1)] if first == 1 else [(u2, u1), (u1, u2)]
        
        turn_logs = []
        
        # 3. Execution Loop
        for att_id, def_id in order:
            s_att_id, s_def_id = str(att_id), str(def_id)
            att_stat, def_stat = (stat1, stat2) if att_id == u1 else (stat2, stat1)
            att_state, def_state = (state1, state2) if att_id == u1 else (state2, state1)
            move_id = move1 if att_id == u1 else move2
            
            md = MOVE_DATA.get(move_id, {})
            turn_logs.append({
                "type": "turn_event", "event_type": "attack_start",
                "attacker": att_id, "defender": def_id,
                "move_id": move_id, "move_type": md.get("type", "normal")
            })
            
            # Hit Check
            is_hit = False
            eff = md.get("effect", {})
            if isinstance(eff, dict) and eff.get("target") == "self": is_hit = True
            elif md.get("type") in ["heal", "buff"]: is_hit = True
            else:
                 from app.game.battle_calculator import BattleCalculator
                 is_hit = BattleCalculator.check_hit(att_stat, att_state, def_stat, def_state, move_id)

            if not is_hit:
                turn_logs.append({
                    "type": "turn_event", "event_type": "hit_result", "result": "miss",
                    "attacker": att_id, "defender": def_id, "message": "공격이 빗나갔습니다!"
                })
            else:
                from app.game.game_assets import PET_TYPE_MAP
                def_pt = room_data["pet_types"][s_def_id]
                def_elem = PET_TYPE_MAP.get(def_pt, "normal")
                
                dmg, is_crit, eff_type = BattleManager.calculate_damage(
                    att_stat, att_state, def_stat, def_state, move_id, 
                    defender_type=def_elem, field_data=room_data["field_effects"]
                )
                
                def_state.current_hp = max(0, def_state.current_hp - dmg)
                
                turn_logs.append({
                     "type":"turn_event", "event_type":"hit_result", "result":"hit",
                     "attacker": att_id, "defender": def_id,
                     "damage": dmg, "defender_hp": def_state.current_hp, "is_critical": is_crit,
                     "message": f"{dmg} 피해!"
                })
                
                if def_state.current_hp > 0:
                    elog = BattleManager.apply_move_effects(move_id, att_state, def_state, att_stat, f"User {att_id}", f"User {def_id}")
                    for l in elog:
                        l["attacker"] = att_id
                        l["defender"] = def_id
                        if l.get("type") == "field_update":
                            room_data["field_effects"][l.get("field")] = l.get("value")
                        turn_logs.append(l)

            if def_state.current_hp <= 0: break

        # Status Effect Damage
        for uid, state, stat in [(u1, state1, stat1), (u2, state2, stat2)]:
            if state.current_hp <= 0: continue 
            dmg, msg, detail = BattleManager.process_status_effects(stat, state)
            if dmg > 0: state.current_hp = max(0, state.current_hp - dmg)
            if detail:
                detail["target"] = uid
                turn_logs.append(detail)
                
        # 4. Save & Broadcast
        room_data["battle_states"][su1] = state1.to_dict()
        room_data["battle_states"][su2] = state2.to_dict()
        room_data["selections"] = {} 
        room_data["turn_count"] += 1
        
        await BattleRoomRepository.clear_selections(self.room_id)
        await BattleRoomRepository.save_room(self.room_id, room_data)
        
        player_states = {
            su1: {"hp": state1.current_hp, "status": [state1.status_ailment] if state1.status_ailment else [], "pp": state1.pp},
            su2: {"hp": state2.current_hp, "status": [state2.status_ailment] if state2.status_ailment else [], "pp": state2.pp}
        }
        
        is_over = state1.current_hp <= 0 or state2.current_hp <= 0
        
        await self.manager.broadcast(self.room_id, {
            "type": "TURN_RESULT",
            "results": turn_logs,
            "player_states": player_states,
            "is_game_over": is_over
        })
        
        if is_over:
            await self._handle_game_end(state1, state2, u1, u2)

    async def _handle_game_end(self, state1, state2, u1, u2):
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

            await self.manager.broadcast(self.room_id, {
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
                    
            await self.manager.send_to_user(self.room_id, winner, {
                "type": "GAME_OVER",
                "result": "WIN",
                "winner": winner,
                "reward": reward_info
            })
            await self.manager.send_to_user(self.room_id, loser, {
                "type": "GAME_OVER",
                "result": "LOSE",
                "winner": winner
            })
            
        await BattleRoomRepository.delete_room(self.room_id)

    async def _process_game_over(self, loser_id, reason="surrender"):
        room_data = await BattleRoomRepository.load_room(self.room_id)
        if not room_data: return
        
        winner_id = None
        for p_id in room_data["players"]:
            if p_id != loser_id:
                winner_id = p_id
                break
        
        if winner_id is not None and winner_id != 0:
             await self.manager.send_to_user(self.room_id, winner_id, {
                "type": "GAME_OVER",
                "result": "WIN",
                "reason": reason,
                "message": "상대방이 대전을 포기했습니다."
            })
             async with AsyncSessionLocal() as db:
                await char_service.process_battle_result(db, winner_id, loser_id)
        
        await BattleRoomRepository.delete_room(self.room_id)
