import random
from app.game.game_assets import MOVE_DATA, STAT_STAGES, STATUS_DATA

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
            "stamina": 0, # speed/agility
            "intelligence": 0,
            "accuracy": 0,
            "evasion": 0
        }
        self.status_ailment = None # poison, paralysis, burn, etc.
        self.status_turns = 0 # 지속 턴 수 (혼란 등)

    def get_stage_multiplier(self, stat_name):
        stage = self.stages.get(stat_name, 0)
        return STAT_STAGES.get(stage, 1.0)

class BattleManager:
    @staticmethod
    def calculate_damage(attacker_stat, attacker_state: BattleState, 
                         defender_stat, defender_state: BattleState, 
                         move_id: int):
        """
        데미지 계산 (스탯 랭크 및 상태 이상 반영)
        """
        move = MOVE_DATA.get(move_id)
        if not move or move["power"] == 0:
            return 0, False

        # 1. 기본 스탯에 랭크업 반영
        atk_mult = attacker_state.get_stage_multiplier("strength")
        def_mult = defender_state.get_stage_multiplier("defense")
        
        attack = int(attacker_stat.strength * atk_mult)
        defense = int(defender_stat.defense * def_mult)
        
        # 화상 상태일 경우 공격력 반감 (물리)
        if attacker_state.status_ailment == "burn":
            attack = int(attack * 0.5)

        if defense < 1: defense = 1

        # 2. 기본 데미지 공식
        level = attacker_stat.level
        power = move["power"]
        
        base_damage = (((2 * level / 5 + 2) * power * attack / defense) / 50) + 2

        # 3. Modifiers
        is_critical = BattleManager.check_critical(attacker_stat.luck)
        crit_multiplier = 1.5 if is_critical else 1.0
        random_multiplier = random.uniform(0.85, 1.0)
        
        final_damage = int(base_damage * crit_multiplier * random_multiplier)
        return final_damage, is_critical



    @staticmethod
    def apply_move_effects(move_id, attacker_state: BattleState, defender_state: BattleState, attacker_stat):
        """
        기술의 부가 효과 적용 (스탯 변화, 상태 이상)
        Return: List[dict] 
        Format: {"type": "stat_change"|"status"|"heal", "detail": ...}
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
                
                # 랭크 제한 (-6 ~ 6)
                current_stage = target_state.stages.get(stat_name, 0)
                new_stage = max(-6, min(6, current_stage + val))
                
                if new_stage != current_stage:
                    target_state.stages[stat_name] = new_stage
                    logs.append({
                        "type": "stat_change",
                        "stat": stat_name,
                        "value": val,
                        "target": effect["target"], # self or enemy
                        "message": f"{stat_name}이(가) {'올라갔습니다' if val > 0 else '떨어졌습니다'}."
                    })
            
            elif effect["type"] == "status":
                status = effect["status"]
                # 이미 상태 이상이 있으면 적용 불가 (단순화)
                if target_state.status_ailment is None:
                    target_state.status_ailment = status
                    target_state.status_turns = random.randint(3, 5)
                    status_name = STATUS_DATA.get(status, {}).get("name", status)
                    logs.append({
                        "type": "status_apply",
                        "status": status,
                        "target": effect["target"],
                        "message": f"{status_name} 상태가 되었습니다!"
                    })
            
            elif effect["type"] == "heal":
                # 힐은 호출부에서 처리할 수도 있지만, 여기서 로깅용 데이터 리턴
                logs.append({
                    "type": "heal",
                    "value": effect["value"],
                    "target": effect["target"],
                    "message": "체력을 회복했습니다!"
                })

        return logs

    @staticmethod
    def check_critical(luck: int) -> bool:
        base_chance = 6.25
        chance = base_chance + (luck * 0.5)
        return random.uniform(0, 100) < chance

    @staticmethod
    def determine_turn_order(stat1, state1: BattleState, move1_id: int, 
                             stat2, state2: BattleState, move2_id: int):
        """
        마비 상태(Paralysis) 고려한 스피드 계산
        """
        speed1 = stat1.stamina * state1.get_stage_multiplier("stamina")
        speed2 = stat2.stamina * state2.get_stage_multiplier("stamina")

        # 마비 시 스피드 50% 반감
        if state1.status_ailment == "paralysis": speed1 *= 0.5
        if state2.status_ailment == "paralysis": speed2 *= 0.5

        if speed1 > speed2: return 1
        elif speed2 > speed1: return 2
        else: return random.choice([1, 2])
    
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
        if state.status_ailment == "paralysis":
            if random.random() < 0.25:
                return False, "몸이 저려서 움직일 수 없습니다!"
        
        # 추후 잠듦, 얼음 등 추가
        return True, None