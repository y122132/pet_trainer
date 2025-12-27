import random
from app.game.game_assets import MOVE_DATA

class BattleCalculator:
    """
    [Battle Math Engine]
    전투의 모든 수치 계산(데미지, 명중률, 선공권)을 담당합니다.
    
    [데미지 계산 공식 가이드]
    1. 공격력(A) / 방어력(D) 계산
       - 물리(Physical): Strength vs Defense
       - 특수(Special): Intelligence vs Intelligence
       - 랭크(Rank) 반영: -6 ~ +6 단계에 따라 보정 (2/8 ~ 8/2)
    2. 화상(Burn) 페널티: 물리 기술일 경우 공격력 50% 반감
    3. 기본 데미지: (A / D) * 위력(Power) * 0.5 + 2
    4. 크리티컬(Critical): (Luck * 0.5 + 5)% 확률로 1.5배 보정
    5. 랜덤 난수(Random): 0.85 ~ 1.0 사이의 값 곱연산
    6. 속성 상성(Type): 효과가 좋음(2.0), 보통(1.0), 별로(0.5), 무효(0.0)
    7. 필드 보정(Field): 날씨(Weather), 장소(Location)에 따른 타입 위력 보정
    """

    @staticmethod
    def calculate_damage(attacker_stat, attacker_state, defender_stat, defender_state, move_id: int, defender_type: str = None, field_data: dict = None):
        """
        [Logic: 데미지 계산]
        위의 공식 가이드에 따라 최종 데미지를 산출합니다.
        Return: (final_damage, is_critical, effectiveness_string)
        """
        move = MOVE_DATA.get(move_id)
        if not move: return 0, False, "normal"

        power = move["power"]
        if power == 0: return 0, False, "normal"

        # 1. 스탯 & 랭크 반영 (Physical/Special Split)
        move_category = move.get("category", "physical")
        
        # Determine Stats based on Category
        if move_category == "special":
            # Special: Intelligence vs Intelligence (Sp.Def)
            atk_val = attacker_stat.intelligence * attacker_state.get_stage_multiplier("intelligence")
            def_val = defender_stat.intelligence * defender_state.get_stage_multiplier("intelligence") 
        elif move_category == "status":
            return 0, False, "normal"
        else:
            # Physical (Default): Strength vs Defense
            atk_val = attacker_stat.strength * attacker_state.get_stage_multiplier("strength")
            def_val = defender_stat.defense * defender_state.get_stage_multiplier("defense")

        # 화상 상태일 경우 (Physical Only) 공격력 반감
        if move_category == "physical" and attacker_state.status_ailment == "burn":
            atk_val *= 0.5
            
        if def_val < 1: def_val = 1
        
        # 2. 기본 데미지
        damage = (atk_val / def_val) * power * 0.5 + 2

        # 3. 크리티컬 (Luck + Crit Stage 기반)
        base_crit = 5.0 + (attacker_stat.luck * 0.5)
        
        crit_stage = attacker_state.stages.get("crit_rate", 0)
        crit_bonus = 0.0
        if crit_stage == 1: crit_bonus = 12.5
        elif crit_stage == 2: crit_bonus = 50.0
        elif crit_stage >= 3: crit_bonus = 100.0
        
        crit_chance = base_crit + crit_bonus
        if crit_chance > 100: crit_chance = 100
        
        is_critical = random.uniform(0, 100) < crit_chance
        crit_multiplier = 1.5 if is_critical else 1.0

        
        # 4. 자속 보정 (STAB - Same Type Attack Bonus)
        # 공격자의 타입과 기술의 타입이 같으면 1.5배 데미지
        stab_multiplier = 1.0
        # Pet Type vs Move Type matching logic needed. 
        # For now, simplistic check if attacker_stat has type info? No, it's in Character object.
        # But here we only have Stat object. 
        # To strictly implement STAB, we need attacker's type passed in.
        # Current signature: (attacker_stat, attacker_state, defender_stat, defender_state, move_id, defender_type, field_data)
        # We don't have attacker_type. We can default to 1.0 or try to infer.
        # Let's clean up the comment first.
        
        # 5. 랜덤 변수 (0.85 ~ 1.0)
        random_factor = random.uniform(0.85, 1.0)

        # [New] 속성 상성 및 면역(Immunity)
        from app.game.game_assets import TYPE_CHART, FIELD_EFECTS
        type_multiplier = 1.0
        move_type = move.get("type", "normal")
        
        if defender_type:
            chart = TYPE_CHART.get(move_type, {})
            weak_list = chart.get("weak", [])
            resist_list = chart.get("resist", [])
            immune_list = chart.get("immune", [])
            
            if defender_type in immune_list:
                type_multiplier = 0.0 # [Deep Logic] Immunity
            elif defender_type in weak_list:
                type_multiplier = 2.0
            elif defender_type in resist_list:
                type_multiplier = 0.5
        
        # [New] Field/Weather Modifiers
        field_multiplier = 1.0
        if field_data:
            weather = field_data.get("weather", "clear")
            location = field_data.get("location", "stadium")
            
            w_chart = FIELD_EFECTS["weather"].get(weather, {})
            if move_type in w_chart:
                field_multiplier *= w_chart[move_type] # e.g. Rain -> Water * 1.5
            
            l_chart = FIELD_EFECTS["location"].get(location, {})
            if move_type in l_chart:
                 field_multiplier *= l_chart[move_type] # e.g. Cave -> Rock * 1.2
        
        final_damage = int(damage * crit_multiplier * type_multiplier * random_factor * field_multiplier)
        if final_damage < 1 and type_multiplier > 0: final_damage = 1
        if type_multiplier == 0: final_damage = 0 # Ensure 0 if immune

        # 효과 결과 반환 (로그용)
        effectiveness = "normal"
        if type_multiplier == 0.0: effectiveness = "immune"
        elif type_multiplier > 1.0: effectiveness = "super"
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