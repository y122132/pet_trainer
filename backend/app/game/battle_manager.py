import random
from app.game.game_assets import MOVE_DATA, STAT_STAGES, STATUS_DATA
from app.game.battle_calculator import BattleCalculator

class BattleState:
    """
    전투 중 일시적으로 유지되는 상태 (스탯 변화, 상태 이상 등)
    DB에 저장하지 않고 메모리 상에서만 존재
    """
    def __init__(self, max_hp: int = 100, current_hp: int = 100):
        self.max_hp = max_hp
        self.current_hp = current_hp
        self.stages = {
            "strength": 0,
            "defense": 0, 
            "agility": 0, # 구 stamina
            "intelligence": 0,
            "accuracy": 0, # 명중률 랭크 (Agility와 별개로 보정 가능)
            "evasion": 0,   # 회피율 랭크 (Agility와 별개로 보정 가능)
            "crit_rate": 0  # [New] 치명타율 랭크 (0~3)
        }
        self.status_ailment = None # poison, paralysis, burn
        self.status_turns = 0 
        
        # [New] Deep Logic State
        self.volatile = {} # {"flinch": 0, "protect": 0, "confusion": 3} -> Name: Turns
        self.pp = {} # {move_id: current_pp} -> To be initialized by Socket
        self.field_data = {} # Per-user field override? No, field is global in Room. 
                             # But maybe individual "Tailwind" (Volatile).
        
    def get_stage_multiplier(self, stat_name):
        stage = self.stages.get(stat_name, 0)
        return STAT_STAGES.get(stage, 1.0)

class BattleManager:
    """
    [Battle System Core]
    전투의 흐름(Flow)을 제어하는 클래스입니다.
    상태(State)를 직접 저장하지 않고, 외부에서 주입받은 BattleState를 조작합니다.
    
    주요 역할:
    1. 데미지 계산 위임 (to BattleCalculator)
    2. 스킬의 부가 효과 적용 (apply_move_effects)
    3. 턴 순서 결정 (determine_turn_order)
    4. 턴 종료 시 상태 이상 처리 (process_status_effects)
    """

    @staticmethod
    def calculate_damage(attacker_stat, attacker_state: BattleState, 
                         defender_stat, defender_state: BattleState, 
                         move_id: int, defender_type: str = None, field_data: dict = None):
        """
        데미지 계산 공식은 복잡하므로 BattleCalculator로 위임합니다.
        """
        return BattleCalculator.calculate_damage(attacker_stat, attacker_state, defender_stat, defender_state, move_id, defender_type, field_data)

    @staticmethod
    def apply_move_effects(move_id, attacker_state: BattleState, defender_state: BattleState, attacker_stat, 
                           attacker_name: str, defender_name: str):
        """
        [Logic: 효과 적용]
        스킬 DB(game_assets.py)에 정의된 'effect' 항목을 처리합니다.
        
        처리 과정:
        1. effect 필드를 리스트로 변환 (단일 효과도 리스트로 처리)
        2. 확률(effect_chance) 체크 (실패 시 빈 리스트 반환)
        3. 각 효과 타입(stat_change, status, field_change, heal)에 따라 분기 처리
        4. 처리 결과를 로그용 Dictionary 리스트로 반환
        """
        move = MOVE_DATA.get(move_id)
        if not move: return []

        logs = []
        raw_effects = move.get("effect")
        chance = move.get("effect_chance", 0)
        
        # [New] Multi-Effect Support
        # Normalize to list
        effects_list = []
        if isinstance(raw_effects, list):
            effects_list = raw_effects
        elif isinstance(raw_effects, dict):
            effects_list = [raw_effects]
        
        # Apply each effect if chance condition met
        # Note: effect_chance usually applies to the *entire* set or per effect?
        # Standard RPG: usually "Secondary effects have X% chance". 
        # For simplicity, we roll ONCE for the whole batch if it's a "secondary effect".
        # But for self-buffs (power 0), chance is usually 100%.
        # Let's assume 'effect_chance' applies to the *probability of side effects occurring*.
        
        if not effects_list: return []
        
        # Roll chance once (or we could roll per effect if needed, but standard is usually all-or-nothing for secondary)
        if random.uniform(0, 100) > chance:
            return []

        for effect in effects_list:
            is_self = effect["target"] == "self"
            target_state = attacker_state if is_self else defender_state
            target_name = attacker_name if is_self else defender_name
            
            if effect["type"] == "stat_change":
                stat_name = effect["stat"]
                val = effect["value"]
                target = effect["target"]
                
                # 랭크 제한 (-6 ~ 6), Crit Rate (0 ~ 3 or similar)
                current_stage = target_state.stages.get(stat_name, 0)
                
                limit_max = 6
                limit_min = -6
                
                # [Refinement] Crit Rate Limit
                if stat_name == "crit_rate":
                    limit_max = 3 # Typically +3 is max for crit
                    limit_min = 0 # Can't go below 0 usually
                
                # [Fix] 스탯 상한선 체크
                if (val > 0 and current_stage >= limit_max) or (val < 0 and current_stage <= limit_min):
                    logs.append({
                        "type": "stat_change",
                        "stat": stat_name,
                        "value": 0,
                        "target": target,
                        "message": f"{target_name}의 {stat_name}은(는) 더 이상 변할 수 없습니다!" 
                    })
                else:
                    new_stage = max(limit_min, min(limit_max, current_stage + val))
                    if new_stage != current_stage:
                        target_state.stages[stat_name] = new_stage
                        val_str = "크게 " if abs(val) > 1 else ""
                        direction = "올라갔습니다" if val > 0 else "떨어졌습니다"
    
                        logs.append({
                            "type": "stat_change",
                            "stat": stat_name,
                            "value": val,
                            "target": target, 
                            "message": f"{target_name}의 {stat_name}이(가) {val_str}{direction}."
                        })
            
            elif effect["type"] == "status":
                status = effect["status"]
                target = effect["target"]
                # 이미 상태 이상이 있으면 적용 불가 (단순화)
                if target_state.status_ailment is None:
                    target_state.status_ailment = status
                    
                    # [Fix] 상태 이상 지속 시간 동적 적용
                    s_data = STATUS_DATA.get(status, {})
                    min_turn = s_data.get("min_turn", 3)
                    max_turn = s_data.get("max_turn", 5)
                    target_state.status_turns = random.randint(min_turn, max_turn)
                    
                    status_name = s_data.get("name", status)
                    logs.append({
                        "type": "status_apply",
                        "status": status,
                        "target": target,
                        "message": f"{status_name} 상태가 되었습니다!"
                    })
            
            # [New] Field Change
            elif effect["type"] == "field_change":
                field_name = effect.get("field", "weather")  # weather or location
                val = effect.get("value", "clear")
                # Message
                if field_name == "weather":
                    label = "날씨"
                    if val == "sun": label = "햇살이 강해졌습니다!"
                    elif val == "rain": label = "비가 내리기 시작했습니다!"
                    elif val == "clear": label = "날씨가 맑아졌습니다!"
                else:
                    label = f"{field_name} 환경이 변했습니다!"
                
                logs.append({
                    "type": "field_update",
                    "field": field_name,
                    "value": val,
                    "message": label
                })

            elif effect["type"] == "heal":
                # [New] 힐링 로직
                amount_pct = effect.get("amount", effect.get("value", 50)) # Support both keys
                target = effect["target"]
                
                if target_state.current_hp > 0:
                    heal_amount = int(target_state.max_hp * (amount_pct / 100)) # Treat val as %
                    # If val is small (e.g. 20), treat as %. 
                    # Note: Previous implementation used 'value' as flat or % ambiguous. 
                    # Plan says "value: 20" in assets.
                    
                    if heal_amount < 1: heal_amount = 1
                    
                    old_hp = target_state.current_hp
                    target_state.current_hp = min(target_state.max_hp, target_state.current_hp + heal_amount)
                    real_healed = target_state.current_hp - old_hp
                    
                    if real_healed > 0:
                        logs.append({
                            "type": "heal",
                            "value": real_healed,
                            "target": target,
                            "message": "체력을 회복했습니다!"
                        })
                    else:
                        logs.append({
                            "type": "heal",
                            "value": 0,
                            "target": target,
                            "message": "체력이 이미 가득 찼습니다!"
                        })



            elif effect["type"] == "recoil":
                # [New] Recoil Logic (for Struggle)
                # value is % of Max HP
                pct = effect.get("value", 25)
                target = effect["target"] # should be 'self' usually
                
                recoil_dmg = int(target_state.max_hp * (pct / 100))
                if recoil_dmg < 1: recoil_dmg = 1
                
                old_hp = target_state.current_hp
                target_state.current_hp = max(0, target_state.current_hp - recoil_dmg)
                real_dmg = old_hp - target_state.current_hp
                
                logs.append({
                    "type": "damage", # Treat as generic damage for visual shake? Or new type? 
                    # Use 'damage_apply' style or specific recoil? 
                    # Existing frontend handles 'damage_apply' well. Let's map it to that or create equivalent log.
                    # Frontend parses 'turn_event' -> 'damage_apply'. 
                    # Here we are in 'apply_move_effects', strictly returning 'logs' list.
                    # The caller (socket) appends these to turn_logs. 
                    # Let's return a log that socket checks? Or just a message? 
                    # Standard Move Effect just returns logs for display usually. 
                    # But Damage IS State Change.
                    # Let's use a type that BattleSocket/Frontend understands or map it.
                    # 'damage_apply' in socket requires 'target' as int ID. Here we have 'target' as 'self' string.
                    # Socket converts 'self'/'enemy'. 
                    # So we can use 'damage_apply' format here if we fit the schema.
                    "type": "turn_event", # Wrapper? No, apply_move_effects returns list of dicts.
                    # Socket iterates and appends.
                    # Socket log schema: {type: turn_event, event_type: damage_apply, damage: X, target: Y}
                    # Wait, BattleManager usually returns simplified logs for Stats/Status.
                    # Socket lines 389: for l in elog: ... turn_logs.append(l)
                    # So we should match socket schema.
                    "type": "turn_event",
                    "event_type": "damage_apply",
                    "damage": real_dmg,
                    "target": target, # 'self' or 'enemy'
                    "message": "반동으로 데미지를 입었습니다!"
                })

        return logs

    @staticmethod
    def determine_turn_order(stat1, state1, move1_id: int, 
                             stat2, state2, move2_id: int):
        """
        선공 결정 위임
        """
        return BattleCalculator.determine_turn_order(stat1, state1, move1_id, stat2, state2, move2_id)
    
    @staticmethod
    def process_status_effects(stat, state: BattleState):
        """
        턴 종료 시 상태 이상 데미지/효과 처리 및 지속시간 감소
        return: (damage_taken, message, detail_dict)
        """
        damage = 0
        msg = None
        detail = None
        
        # [New] Process Volatile Statuses First
        # Flinch and Protect usually last 1 turn and clear automatically at END of turn (or start of next).
        # Here we clear them if they expired? 
        # Actually Flinch is "this turn only". So clear it.
        if "flinch" in state.volatile:
            del state.volatile["flinch"]
            # No message needed for clearing flinch usually, it just wears off.

        if "protect" in state.volatile:
            del state.volatile["protect"]
            
        # [Fix] Confusion (Moved to Volatile in Asset, but logic might still be mixed. Let's fully migrate logic if possible)
        # For now, handle 'confusion' in volatile dict if present.
        if "confusion" in state.volatile:
            state.volatile["confusion"] -= 1
            if state.volatile["confusion"] <= 0:
                del state.volatile["confusion"]
                msg = "혼란이 풀렸습니다!"
                # Append to detail if exists? 
                # Ideally return list of messages. For now, prioritize ailment msg.

        if state.status_ailment:
            # [Fix] Apply Logic First (Damage), Then Decrement
            
            # 1. Calculate Damage/Effect
            if state.status_ailment == "poison":
                damage = int(state.max_hp / 8)
                if damage < 1: damage = 1
                msg = "독으로 인해 피해를 입었습니다!"
                
            elif state.status_ailment == "burn":
                damage = int(state.max_hp / 8)
                if damage < 1: damage = 1
                msg = "화상으로 인해 고통스럽습니다!"
            
            # 2. Decrement Turn
            state.status_turns -= 1
            
            # 3. Prepare Return Logic
            detail = {
                "type": "status_damage",
                "status": state.status_ailment,
                "damage": damage,
                "message": msg
            } if msg else None
            
            # 4. Check Expiration
            if state.status_turns <= 0:
                prev_status = state.status_ailment
                state.status_ailment = None
                status_name = STATUS_DATA.get(prev_status, {}).get("name", prev_status)
                
                recover_msg = f"{status_name} 상태에서 회복되었습니다!"
                
                if msg:
                     msg += f" (그리고 {status_name} 상태에서 회복되었습니다!)"
                     detail["message"] = msg
                     detail["is_recovered"] = True 
                else:
                     msg = recover_msg
                     detail = {
                        "type": "status_recover",
                        "status": prev_status,
                        "message": recover_msg
                     }
            
            return damage, msg, detail
            
        return damage, msg, detail

    @staticmethod
    def can_move(state: BattleState):
        """
        상태 이상으로 인한 행동 불가 체크
        Return: (can_move: bool, message: str, self_damage: int)
        """
        # [New] Volatile: Flinch
        if "flinch" in state.volatile:
             return False, "풀죽어서 움직일 수 없습니다!", 0

        # [Fix] 혼란 (Confusion) - Check Volatile First
        if "confusion" in state.volatile:
            # 33% 확률로 자해
            if random.random() < 0.33:
                # 자해 데미지 계산 (최대 체력의 10% 정도?)
                self_damage = int(state.max_hp * 0.1)
                if self_damage < 1: self_damage = 1
                
                state.current_hp -= self_damage
                if state.current_hp < 0: state.current_hp = 0
                
                return False, f"혼란에 빠져 자신을 공격했습니다!", self_damage

        # 마비 (Paralysis) 체크
        if state.status_ailment == "paralysis":
            if random.random() < 0.25:
                # 25% 확률로 행동 불가
                return False, "몸이 저려서 움직일 수 없습니다!", 0
        
        # 수면 (Sleep) - Not implemented yet but placeholder
        if state.status_ailment == "sleep":
             return False, "쿨쿨 자고 있습니다.", 0

        return True, None, 0