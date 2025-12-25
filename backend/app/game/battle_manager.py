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
            "evasion": 0   # 회피율 랭크 (Agility와 별개로 보정 가능)
        }
        self.status_ailment = None # poison, paralysis, burn, etc.
        self.status_turns = 0 # 지속 턴 수

    def get_stage_multiplier(self, stat_name):
        stage = self.stages.get(stat_name, 0)
        return STAT_STAGES.get(stage, 1.0)

class BattleManager:
    @staticmethod
    def calculate_damage(attacker_stat, attacker_state: BattleState, 
                         defender_stat, defender_state: BattleState, 
                         move_id: int, defender_type: str = None):
        """
        데미지 계산 위임
        """
        return BattleCalculator.calculate_damage(attacker_stat, attacker_state, defender_stat, defender_state, move_id, defender_type)

    @staticmethod
    def apply_move_effects(move_id, attacker_state: BattleState, defender_state: BattleState, attacker_stat):
        """
        기술의 부가 효과 적용 (스탯 변화, 상태 이상, 힐링)
        Return: List[dict] 
        """
        move = MOVE_DATA.get(move_id)
        if not move: return []

        logs = []
        effect = move.get("effect")
        chance = move.get("effect_chance", 0)

        if effect and random.uniform(0, 100) < chance:
            target_state = attacker_state if effect["target"] == "self" else defender_state
            
            if effect["type"] == "stat_change":
                stat_name = effect["stat"]
                val = effect["value"]
                target = effect["target"]
                
                # 랭크 제한 (-6 ~ 6)
                current_stage = target_state.stages.get(stat_name, 0)
                
                # [Fix] 스탯 상한선 체크 (-6 ~ +6)
                if (val > 0 and current_stage >= 6) or (val < 0 and current_stage <= -6):
                    logs.append({
                        "type": "stat_change",
                        "stat": stat_name,
                        "value": 0,
                        "target": target,
                        "message": f"{target_name} {stat_name}은(는) 더 이상 변할 수 없습니다!" 
                    })
                else:
                    new_stage = max(-6, min(6, current_stage + val))
                    if new_stage != current_stage:
                        target_state.stages[stat_name] = new_stage
                        val_str = "크게 " if abs(val) > 1 else ""
                        direction = "올라갔습니다" if val > 0 else "떨어졌습니다"
    
                        logs.append({
                            "type": "stat_change",
                            "stat": stat_name,
                            "value": val,
                            "target": target, 
                            "message": f"{target_name} {stat_name}이(가) {val_str}{direction}."
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
            
            elif effect["type"] == "heal":
                # [New] 힐링 로직
                amount_pct = effect.get("amount", 50) # 기본 50%
                target = effect["target"]
                
                if target_state.current_hp > 0:
                    heal_amount = int(target_state.max_hp * (amount_pct / 100))
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
        
        if state.status_ailment:
            # 지속 턴 감소
            state.status_turns -= 1
            if state.status_turns <= 0:
                # 상태 회복
                prev_status = state.status_ailment
                state.status_ailment = None
                status_name = STATUS_DATA.get(prev_status, {}).get("name", prev_status)
                return 0, f"{status_name} 상태에서 회복되었습니다!", {
                    "type": "status_recover",
                    "status": prev_status,
                    "message": f"{status_name} 상태에서 회복되었습니다!"
                }

            if state.status_ailment == "poison":
                damage = int(state.max_hp / 8) # Max HP 기준
                if damage < 1: damage = 1
                msg = "독으로 인해 피해를 입었습니다!"
                
            elif state.status_ailment == "burn":
                damage = int(state.max_hp / 8) # Max HP 기준
                if damage < 1: damage = 1
                msg = "화상으로 인해 고통스럽습니다!"
            
        return damage, msg, {
            "type": "status_damage",
            "status": state.status_ailment,
            "damage": damage,
            "message": msg
        } if msg else None

    @staticmethod
    def can_move(state: BattleState):
        """
        상태 이상으로 인한 행동 불가 체크
        """
        # [Fix] 혼란 (Confusion) 체크
        if state.status_ailment == "confusion":
            # 33% 확률로 자해
            if random.random() < 0.33:
                # 자해 데미지 계산 (최대 체력의 10% 정도?)
                self_damage = int(state.max_hp * 0.1)
                if self_damage < 1: self_damage = 1
                
                state.current_hp -= self_damage
                if state.current_hp < 0: state.current_hp = 0
                
                return False, f"혼란에 빠져 자신을 공격했습니다! (피해: {self_damage})"

        # 마비 (Paralysis) 체크
        if state.status_ailment == "paralysis":
            if random.random() < 0.25:
                # 25% 확률로 행동 불가
                return False, "몸이 저려서 움직일 수 없습니다!"
        
        return True, None