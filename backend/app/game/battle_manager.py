import random
from typing import List, Dict, Any, Optional
from abc import ABC, abstractmethod
from app.game.game_assets import MOVE_DATA, STAT_STAGES, STATUS_DATA
from app.game.battle_calculator import BattleCalculator

class BattleState:
    """
    전투 중 일시적으로 유지되는 상태 (스탯 변화, 상태 이상 등)
    """
    def __init__(self, max_hp: int = 100, current_hp: int = 100):
        self.max_hp = max_hp
        self.current_hp = current_hp
        self.stages = {
            "strength": 0, "defense": 0, "agility": 0, "intelligence": 0,
            "accuracy": 0, "evasion": 0, "crit_rate": 0
        }
        self.status_ailment = None # poison, paralysis, burn
        self.status_turns = 0 
        self.volatile = {} # {"flinch": 0, "protect": 0, "confusion": 3}
        self.pp = {} 

    def get_stage_multiplier(self, stat_name):
        stage = self.stages.get(stat_name, 0)
        return STAT_STAGES.get(stage, 1.0)
    
    def to_dict(self) -> Dict[str, Any]:
        """Redis 저장을 위한 직렬화"""
        return {
            "max_hp": self.max_hp,
            "current_hp": self.current_hp,
            "stages": self.stages,
            "status_ailment": self.status_ailment,
            "status_turns": self.status_turns,
            "volatile": self.volatile,
            "pp": self.pp
        }

    @staticmethod
    def from_dict(data: Dict[str, Any]) -> 'BattleState':
        """Redis 데이터로부터 상태 복원"""
        bs = BattleState(max_hp=data.get("max_hp", 100), current_hp=data.get("current_hp", 100))
        bs.stages = data.get("stages", bs.stages)
        bs.status_ailment = data.get("status_ailment")
        bs.status_turns = data.get("status_turns", 0)
        bs.volatile = data.get("volatile", {})
        bs.pp = data.get("pp", {})
        return bs

# --- [Strategy Pattern Interfaces] ---
class EffectStrategy(ABC):
    @abstractmethod
    def apply(self, effect: dict, attacker_state: BattleState, defender_state: BattleState, 
              attacker_name: str, defender_name: str) -> Optional[dict]:
        """
        효과를 적용하고 로그(dict)를 반환합니다. 효과가 없으면 None.
        """
        pass

# --- [Concrete Strategies] ---
class StatChangeStrategy(EffectStrategy):
    def apply(self, effect, attacker_state, defender_state, attacker_name, defender_name):
        stat_name = effect["stat"]
        val = effect["value"]
        target = effect["target"]
        
        target_state = attacker_state if target == "self" else defender_state
        target_name = attacker_name if target == "self" else defender_name
        
        current_stage = target_state.stages.get(stat_name, 0)
        limit_max = 3 if stat_name == "crit_rate" else 6
        limit_min = 0 if stat_name == "crit_rate" else -6
        
        if (val > 0 and current_stage >= limit_max) or (val < 0 and current_stage <= limit_min):
            return {
                "type": "stat_change", 
                "stat": stat_name, 
                "value": 0, 
                "target": target,
                "message": f"{target_name}의 {stat_name}은(는) 더 이상 변할 수 없습니다!"
            }
            
        new_stage = max(limit_min, min(limit_max, current_stage + val))
        if new_stage != current_stage:
            target_state.stages[stat_name] = new_stage
            val_str = "크게 " if abs(val) > 1 else ""
            direction = "올라갔습니다" if val > 0 else "떨어졌습니다"
            
            return {
                "type": "stat_change", 
                "stat": stat_name, 
                "value": val, 
                "target": target,
                "message": f"{target_name}의 {stat_name}이(가) {val_str}{direction}."
            }
        return None

class StatusStrategy(EffectStrategy):
    def apply(self, effect, attacker_state, defender_state, attacker_name, defender_name):
        status = effect["status"]
        target = effect["target"]
        target_state = attacker_state if target == "self" else defender_state
        
        if target_state.status_ailment is None:
            target_state.status_ailment = status
            s_data = STATUS_DATA.get(status, {})
            # 상태 이상 지속 시간 설정
            min_turn = s_data.get("min_turn", 2)
            max_turn = s_data.get("max_turn", 5)
            target_state.status_turns = random.randint(min_turn, max_turn)
            
            status_name = s_data.get("name", status)
            return {
                "type": "status_apply", 
                "status": status, 
                "target": target,
                "message": f"{status_name} 상태가 되었습니다!"
            }
        return None

class HealStrategy(EffectStrategy):
    def apply(self, effect, attacker_state, defender_state, attacker_name, defender_name):
        amount_pct = effect.get("amount", effect.get("value", 50))
        target = effect["target"]
        target_state = attacker_state if target == "self" else defender_state
        
        if target_state.current_hp > 0:
            heal_amount = int(target_state.max_hp * (amount_pct / 100))
            if heal_amount < 1: heal_amount = 1
            
            old_hp = target_state.current_hp
            target_state.current_hp = min(target_state.max_hp, target_state.current_hp + heal_amount)
            real_healed = target_state.current_hp - old_hp
            
            msg = "체력을 회복했습니다!" if real_healed > 0 else "체력이 이미 가득 찼습니다!"
            return {
                "type": "heal", 
                "value": real_healed, 
                "target": target, 
                "message": msg
            }
        return None

class FieldStrategy(EffectStrategy):
    def apply(self, effect, attacker_state, defender_state, attacker_name, defender_name):
        field_name = effect.get("field", "weather")
        val = effect.get("value", "clear")
        
        label = "날씨"
        if field_name == "weather":
            if val == "sun": label = "햇살이 강해졌습니다!"
            elif val == "rain": label = "비가 내리기 시작했습니다!"
            elif val == "clear": label = "날씨가 맑아졌습니다!"
        else:
            label = f"{field_name} 환경이 변했습니다!"
            
        return {
            "type": "field_update", 
            "field": field_name, 
            "value": val, 
            "message": label
        }

class RecoilStrategy(EffectStrategy):
    def apply(self, effect, attacker_state, defender_state, attacker_name, defender_name):
        pct = effect.get("value", 25)
        target = effect["target"]
        target_state = attacker_state if target == "self" else defender_state
        
        dmg = int(target_state.max_hp * (pct / 100))
        if dmg < 1: dmg = 1
        
        target_state.current_hp = max(0, target_state.current_hp - dmg)
        
        return {
            "type": "turn_event", 
            "event_type": "damage_apply", 
            "damage": dmg, 
            "target": target,
            "message": "반동으로 데미지를 입었습니다!"
        }

# --- [BattleManager Core] ---
class BattleManager:
    """
    [Battle System Core]
    전투 흐름 제어 및 Strategy Pattern 적용
    """
    
    # 전략 등록
    _strategies: Dict[str, EffectStrategy] = {
        "stat_change": StatChangeStrategy(),
        "status": StatusStrategy(),
        "field_change": FieldStrategy(),
        "heal": HealStrategy(),
        "recoil": RecoilStrategy()
    }

    @staticmethod
    def calculate_damage(attacker_stat, attacker_state, defender_stat, defender_state, move_id, defender_type=None, field_data=None):
        return BattleCalculator.calculate_damage(attacker_stat, attacker_state, defender_stat, defender_state, move_id, defender_type, field_data)

    @classmethod
    def apply_move_effects(cls, move_id, attacker_state: BattleState, defender_state: BattleState, attacker_stat, 
                           attacker_name: str, defender_name: str) -> List[Dict]:
        """
        Strategy Pattern을 사용하여 스킬 효과를 적용합니다.
        이제 거대한 if-else 문 대신 각 전략 객체가 로직을 수행합니다.
        """
        move = MOVE_DATA.get(move_id)
        if not move: return []

        logs = []
        raw_effects = move.get("effect")
        chance = move.get("effect_chance", 0)
        
        # Normalize to list
        effects_list = []
        if isinstance(raw_effects, list):
            effects_list = raw_effects
        elif isinstance(raw_effects, dict):
            effects_list = [raw_effects]
        
        if not effects_list: return []
        
        # 확률 체크 (전체 효과에 대해 한 번 체크)
        if random.uniform(0, 100) > chance:
            return []

        for effect in effects_list:
            etype = effect.get("type", "")
            strategy = cls._strategies.get(etype)
            
            if strategy:
                log = strategy.apply(effect, attacker_state, defender_state, attacker_name, defender_name)
                if log:
                    logs.append(log)
            else:
                pass # Unknown effect type
        
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