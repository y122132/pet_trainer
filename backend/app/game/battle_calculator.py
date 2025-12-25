import random
from app.game.game_assets import MOVE_DATA

class BattleCalculator:
    """
    배틀의 모든 수치를 계산하는 핵심 엔진 (고도화 버전)
    7대 스탯 활용: Health, Strength, Agility, Intelligence, Defense, Luck
    """

    @staticmethod
    def calculate_damage(attacker_stat, attacker_state, defender_stat, defender_state, move_id: int, defender_type: str = None):
        """
        데미지 공식: (Strength / Defense) * Power * Modifiers
        """
        move = MOVE_DATA.get(move_id)
        if not move: return 0, False, "normal"

        power = move["power"]
        if power == 0: return 0, False, "normal"

        # 1. 스탯 & 랭크 반영 (Agility, Strength, Defense 등)
        # 물리 공격: Strength / 방어: Defense
        # (추후 특수 공격 구분 시 Intelligence 사용 가능)
        atk_val = attacker_stat.strength * attacker_state.get_stage_multiplier("strength")
        def_val = defender_stat.defense * defender_state.get_stage_multiplier("defense")

        # 화상 상태일 경우 공격력 반감
        if attacker_state.status_ailment == "burn":
            atk_val *= 0.5
            
        if def_val < 1: def_val = 1
        
        # 2. 기본 데미지
        # (공격력 / 방어력) 비율에 기술 위력을 곱함 + 상수 보정
        damage = (atk_val / def_val) * power * 0.5 + 2

        # 3. 크리티컬 (Luck + Crit Stage 기반)
        # 기본 5% + (Luck * 0.5)%
        base_crit = 5.0 + (attacker_stat.luck * 0.5)
        
        # [New] Crit Stage Bonus
        # 0: +0%, 1: +12.5%, 2: +50%, 3: +100%
        crit_stage = attacker_state.stages.get("crit_rate", 0)
        crit_bonus = 0.0
        if crit_stage == 1: crit_bonus = 12.5
        elif crit_stage == 2: crit_bonus = 50.0
        elif crit_stage >= 3: crit_bonus = 100.0
        
        crit_chance = base_crit + crit_bonus
        
        # 최대 100% 제한 (was 50)
        if crit_chance > 100: crit_chance = 100
        
        is_critical = random.uniform(0, 100) < crit_chance
        crit_multiplier = 1.5 if is_critical else 1.0

        # ... (Rest of logic) ...

        # 4. 랜덤 변수 (0.85 ~ 1.0)
        random_factor = random.uniform(0.85, 1.0)

        # [New] 속성 상성 적용
        from app.game.game_assets import TYPE_CHART
        type_multiplier = 1.0
        
        move_type = move.get("type", "normal")
        if defender_type:
            chart = TYPE_CHART.get(move_type, {})
            weak_list = chart.get("weak", [])
            resist_list = chart.get("resist", [])
            
            if defender_type in weak_list:
                type_multiplier = 2.0
            elif defender_type in resist_list:
                type_multiplier = 0.5
        
        final_damage = int(damage * crit_multiplier * type_multiplier * random_factor)
        if final_damage < 1: final_damage = 1

        # 효과 결과 반환 (로그용)
        effectiveness = "normal"
        if type_multiplier > 1.0: effectiveness = "super"
        elif type_multiplier < 1.0: effectiveness = "not_very"

        # [Important] Return correct unpacking 3 items
        return final_damage, is_critical, effectiveness

    @staticmethod
    def check_hit(attacker_stat, attacker_state, defender_stat, defender_state, move_id: int) -> bool:
        """
        명중 여부 판정: Accuracy * (Atk Agility / Def Agility) * Stage Modifiers
        """
        move = MOVE_DATA.get(move_id)
        if not move: return False
            
        accuracy = move.get("accuracy", 100)
        if accuracy >= 1000: return True # 필중

        # [New] Stage Logic (Accuracy vs Evasion)
        atk_acc_stage = attacker_state.stages.get("accuracy", 0)
        def_eva_stage = defender_state.stages.get("evasion", 0)
        
        # Combine stages: (Attacker Acc - Defender Eva)
        # Standard table: -6 to +6 maps to multipliers
        # Formula:
        # If stage >= 0: (3 + stage) / 3
        # If stage < 0:  3 / (3 + abs(stage))
        
        net_stage = atk_acc_stage - def_eva_stage
        net_stage = max(-6, min(6, net_stage)) # clamp
        
        stage_multiplier = 1.0
        if net_stage >= 0:
            stage_multiplier = (3.0 + net_stage) / 3.0
        else:
            stage_multiplier = 3.0 / (3.0 + abs(net_stage))

        # Agility 기반 보정 (Still keep Agility as base factor?)
        # Yes, Plan says: accuracy * (atk_agi / def_agi) * stage_multiplier
        atk_agi = attacker_stat.agility * attacker_state.get_stage_multiplier("agility")
        def_agi = defender_stat.agility * defender_state.get_stage_multiplier("agility") 
        
        if atk_agi < 1: atk_agi = 1
        if def_agi < 1: def_agi = 1
        
        # Calculation
        hit_chance = accuracy * (atk_agi / def_agi) * stage_multiplier
        
        # 최소/최대 보정
        if hit_chance < 20: hit_chance = 20
        if hit_chance > 100: hit_chance = 100
        
        return random.uniform(0, 100) <= hit_chance

    @staticmethod
    def determine_turn_order(stat1, state1, move1_id: int, stat2, state2, move2_id: int) -> int:
        """
        선공 결정: 1. 우선도 -> 2. Agility
        """
        move1 = MOVE_DATA.get(move1_id, {})
        move2 = MOVE_DATA.get(move2_id, {})
        
        prio1 = move1.get("priority", 0)
        prio2 = move2.get("priority", 0)
        
        if prio1 > prio2: return 1
        if prio2 > prio1: return 2
        
        # 우선도 동일 시 Agility 비교
        agi1 = stat1.agility * state1.get_stage_multiplier("agility")
        agi2 = stat2.agility * state2.get_stage_multiplier("agility")

        # 마비 패널티 (속도 50% 감소)
        if state1.status_ailment == "paralysis": agi1 *= 0.5
        if state2.status_ailment == "paralysis": agi2 *= 0.5

        if agi1 > agi2: return 1
        elif agi2 > agi1: return 2
        else: return random.choice([1, 2])