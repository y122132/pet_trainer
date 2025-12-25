# --- 게임 에셋 (Game Assets) ---
# 이 파일은 배틀 시스템에서 사용하는 모든 정적 데이터를 정의합니다.

# 1. Skill_Database: 각 스킬의 이름, 위력, 명중률, 속성, 설명, 부가 효과 등
# effect 구조: {"type": "stat_change"|"status", "stat": str, "value": int, "target": "self"|"enemy", "status": str}
MOVE_DATA = {
    1: {
        "name": "짖기", 
        "power": 20, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "special", # [New] Sound based = Special
        "description": "큰 소리로 짖어 상대를 놀라게 한다.",
        "effect": {"type": "stat_change", "stat": "defense", "value": -1, "target": "enemy"},
        "effect_chance": 30
    },
    2: {
        "name": "버티기", 
        "power": 0, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "status",
        "description": "공격을 버텨내며 방어력을 높인다.",
        "effect": {"type": "stat_change", "stat": "defense", "value": 1, "target": "self"},
        "effect_chance": 100
    },
    3: {
        "name": "회복 본능", 
        "power": 0, 
        "accuracy": 100, 
        "type": "heal", 
        "category": "status",
        "description": "체력을 약간 회복한다.",
        "effect": {"type": "heal", "value": 20, "target": "self"}, 
        "effect_chance": 100
    },
    4: {
        "name": "꼬리 살랑", 
        "power": 0, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "status",
        "description": "방심하게 만들어 상대의 방어력을 낮춘다.",
        "effect": {"type": "stat_change", "stat": "defense", "value": -1, "target": "enemy"},
        "effect_chance": 100
    },
    5: {
        "name": "간식 발견", 
        "power": 40, 
        "accuracy": 90, 
        "type": "normal", 
        "category": "physical",
        "description": "간식을 발견한 기쁨으로 돌진한다.",
        "effect": {"type": "stat_change", "stat": "strength", "value": 1, "target": "self"},
        "effect_chance": 50
    },
    6: {
        "name": "전광석화",
        "power": 40,
        "accuracy": 100,
        "type": "normal", 
        "category": "physical",
        "priority": 1, 
        "description": "눈에 보이지 않는 속도로 먼저 공격한다.",
        "effect": None,
        "effect_chance": 0
    },
    
    101: {
        "name": "할퀴기", 
        "power": 35, 
        "accuracy": 95, 
        "type": "normal", 
        "category": "physical",
        "description": "날카로운 발톱으로 상대를 할퀸다. (확률적 출혈/독)",
        "effect": {"type": "status", "status": "poison", "target": "enemy"},
        "effect_chance": 30
    },
    102: {
        "name": "냥점프", 
        "power": 0, 
        "accuracy": 100, 
        "type": "evade", 
        "category": "status",
        "description": "높이 점프하여 회피율(민첩성)을 높인다.",
        "effect": {"type": "stat_change", "stat": "agility", "value": 1, "target": "self"},
        "effect_chance": 100
    },
    103: {
        "name": "신경 긁기", 
        "power": 15, 
        "accuracy": 100, 
        "type": "psychic", 
        "category": "special",
        "description": "상대의 신경을 긁어 공격력을 낮춘다.",
        "effect": {"type": "stat_change", "stat": "strength", "value": -1, "target": "enemy"},
        "effect_chance": 100
    },
    104: {
        "name": "급습", 
        "power": 40, 
        "accuracy": 100, 
        "type": "dark", 
        "category": "physical",
        "description": "보이지 않는 곳에서 기습한다. (높은 크리티컬/마비)",
        "effect": {"type": "status", "status": "paralysis", "target": "enemy"},
        "effect_chance": 10
    },
    105: {
        "name": "냥냥펀치", 
        "power": 15, 
        "accuracy": 90, 
        "type": "fighting", 
        "category": "physical",
        "description": "연속 펀치. 상대를 혼란에 빠뜨릴 수 있다.",
        "effect": {"type": "status", "status": "confusion", "target": "enemy"},
        "effect_chance": 20
    }
}

# 2. Type_Chart: 속성 상성 (공격 타입 기준)
# weak: 2배 데미지를 입히는 방어 타입
# resist: 0.5배 데미지를 입히는 방어 타입 (반감)
TYPE_CHART = {
    "normal": {"weak": [], "resist": ["rock", "steel"]},
    "fighting": {"weak": ["normal", "rock", "steel", "ice", "dark"], "resist": ["flying", "poison", "bug", "psychic", "fairy"]},
    "flying": {"weak": ["fighting", "bug", "grass"], "resist": ["rock", "steel", "electric"]},
    "poison": {"weak": ["grass", "fairy"], "resist": ["poison", "ground", "rock", "ghost"]},
    "ground": {"weak": ["poison", "rock", "steel", "fire", "electric"], "resist": ["bug", "grass"]},
    "rock": {"weak": ["flying", "bug", "fire", "ice"], "resist": ["fighting", "ground", "steel"]},
    "bug": {"weak": ["grass", "psychic", "dark"], "resist": ["fighting", "flying", "poison", "ghost", "steel", "fire", "fairy"]},
    "ghost": {"weak": ["ghost", "psychic"], "resist": ["dark"]},
    "steel": {"weak": ["rock", "ice", "fairy"], "resist": ["steel", "fire", "water", "electric"]},
    "fire": {"weak": ["bug", "steel", "grass", "ice"], "resist": ["rock", "fire", "water", "dragon"]},
    "water": {"weak": ["ground", "rock", "fire"], "resist": ["water", "grass", "dragon"]},
    "grass": {"weak": ["ground", "rock", "water"], "resist": ["flying", "poison", "bug", "steel", "fire", "grass", "dragon"]},
    "electric": {"weak": ["flying", "water"], "resist": ["grass", "electric", "dragon"]},
    "psychic": {"weak": ["fighting", "poison"], "resist": ["steel", "psychic"]},
    "ice": {"weak": ["flying", "ground", "grass", "dragon"], "resist": ["steel", "fire", "water", "ice"]},
    "dragon": {"weak": ["dragon"], "resist": ["steel"]},
    "dark": {"weak": ["ghost", "psychic"], "resist": ["fighting", "dark", "fairy"]},
    "fairy": {"weak": ["fighting", "dragon", "dark"], "resist": ["poison", "steel", "fire"]}
}

# [New] 펫 종류별 속성 매핑 (임시)
PET_TYPE_MAP = {
    "dog": "normal",
    "cat": "normal", # 테스트를 위해 fighting으로 변경 가능
    "bird": "flying"
}

# 3. PET_LEARNSET: 펫 종류에 따른 기술 습득 테이블 (No Change needed here, logical mapping)
PET_LEARNSET = {
    "dog": {
        1: [1, 2],       
        5: [3, 4],       
        10: [5]          
    },
    "cat": {
        1: [101, 102],   
        5: [103, 104],   
        10: [105]        
    }
}

# 4. Status Effects Info (Re-organized)
STATUS_DATA = {
    # Persistent (Ailment)
    "poison": {"name": "독", "desc": "매 턴 체력의 1/8 피해", "min_turn": 3, "max_turn": 6},
    "paralysis": {"name": "마비", "desc": "스피드 저하 및 25% 확률로 행동 불가", "min_turn": 2, "max_turn": 5},
    "burn": {"name": "화상", "desc": "매 턴 체력 피해 및 공격력 반감", "min_turn": 3, "max_turn": 6},
    
    # Volatile (New) - Logic handled in Manager, Descriptions here for UI if needed
    "confusion": {"name": "혼란", "desc": "33% 확률로 자해 데미지", "min_turn": 2, "max_turn": 5},
    "flinch": {"name": "풀죽음", "desc": "놀라서 움직일 수 없다", "min_turn": 1, "max_turn": 1},
    "protect": {"name": "방어", "desc": "이번 턴의 공격을 막는다", "min_turn": 1, "max_turn": 1}
}

# 5. Stat Stages Multiplier
STAT_STAGES = {
    -6: 2/8, -5: 2/7, -4: 2/6, -3: 2/5, -2: 2/4, -1: 2/3,
    0: 1.0,
    1: 3/2, 2: 4/2, 3: 5/2, 4: 6/2, 5: 7/2, 6: 8/2
}

# 6. [New] Type Immunity Update (Fixed Direction)
# Key = Attacking Type, Value = List of Immune Defender Types
TYPE_CHART["ground"]["immune"] = ["flying"]
TYPE_CHART["ghost"]["immune"] = ["normal"] # Normal is Immune to Ghost? No, usually Normal is imm to Ghost AND Ghost imm to Normal.
# Ghost moves -> Normal (0x)
# Normal moves -> Ghost (0x)
TYPE_CHART["normal"]["immune"] = ["ghost"]
TYPE_CHART["electric"]["immune"] = ["ground"]
TYPE_CHART["psychic"]["immune"] = ["dark"]
TYPE_CHART["poison"]["immune"] = ["steel"]
TYPE_CHART["dragon"]["immune"] = ["fairy"]
# Fighting moves -> Ghost (0x)
TYPE_CHART["fighting"]["immune"] = ["ghost"]

# 7. [New] Field & Weather Modifiers
FIELD_EFECTS = {
    "weather": {
        "sun": {"fire": 1.5, "water": 0.5, "name": "쾌청"},
        "rain": {"water": 1.5, "fire": 0.5, "name": "비"},
        "clear": {"name": "맑음"}
    },
    "location": {
        "stadium": {"name": "경기장"}, # No bonus
        "cave": {"rock": 1.2, "ground": 1.2, "name": "동굴"},
        "forest": {"grass": 1.2, "bug": 1.2, "name": "숲"},
        "water": {"water": 1.2, "name": "물가"}
    }
}

# 8. [New] Species Base Stats (종족값)
PET_BASE_STATS = {
    "dog": {"strength": 10, "intelligence": 10, "defense": 10, "agility": 10, "luck": 10}, # Balanced
    "cat": {"strength": 9, "intelligence": 12, "defense": 8, "agility": 14, "luck": 12},  # Fast Special Attacker
    "bird": {"strength": 9, "intelligence": 9, "defense": 8, "agility": 15, "luck": 10},  # Fast Mixed
    "bear": {"strength": 15, "intelligence": 5, "defense": 14, "agility": 6, "luck": 10}, # Physical Tank
    "robot": {"strength": 12, "intelligence": 12, "defense": 12, "agility": 8, "luck": 10} # Durable Mixed
}

# 9. Additional Moves Injection (Elemental & Strategic)
# Fire
MOVE_DATA[201] = {"name": "불꽃세례", "type": "fire", "category": "special", "power": 40, "accuracy": 100, "description": "작은 불꽃을 발사한다.", "effect": {"type": "status", "status": "burn", "target": "enemy"}, "effect_chance": 10}
MOVE_DATA[202] = {"name": "화염방사", "type": "fire", "category": "special", "power": 90, "accuracy": 100, "description": "강렬한 불꽃을 내뿜는다.", "effect": {"type": "status", "status": "burn", "target": "enemy"}, "effect_chance": 10}
MOVE_DATA[203] = {"name": "불꽃엄니", "type": "fire", "category": "physical", "power": 65, "accuracy": 95, "description": "불꽃을 머금은 이빨로 문다.", "effect": {"type": "status", "status": "burn", "target": "enemy"}, "effect_chance": 10}
MOVE_DATA[204] = {"name": "도깨비불", "type": "fire", "category": "status", "power": 0, "accuracy": 85, "description": "도깨비불로 상대를 화상 입힌다.", "effect": {"type": "status", "status": "burn", "target": "enemy"}, "effect_chance": 100}

# Water
MOVE_DATA[211] = {"name": "물대포", "type": "water", "category": "special", "power": 40, "accuracy": 100, "description": "물을 발사한다.", "effect": None, "effect_chance": 0}
MOVE_DATA[212] = {"name": "하이드로펌프", "type": "water", "category": "special", "power": 110, "accuracy": 80, "description": "고압의 물을 발사한다.", "effect": None, "effect_chance": 0}
MOVE_DATA[213] = {"name": "폭포오르기", "type": "water", "category": "physical", "power": 80, "accuracy": 100, "description": "기세 좋게 돌진한다. (풀죽음)", "effect": {"type": "status", "status": "flinch", "target": "enemy"}, "effect_chance": 20}

# Electric
MOVE_DATA[221] = {"name": "전기쇼크", "type": "electric", "category": "special", "power": 40, "accuracy": 100, "description": "전기를 흘려보낸다.", "effect": {"type": "status", "status": "paralysis", "target": "enemy"}, "effect_chance": 10}
MOVE_DATA[222] = {"name": "10만볼트", "type": "electric", "category": "special", "power": 90, "accuracy": 100, "description": "강력한 전류를 발사한다.", "effect": {"type": "status", "status": "paralysis", "target": "enemy"}, "effect_chance": 10}
MOVE_DATA[223] = {"name": "번개엄니", "type": "electric", "category": "physical", "power": 65, "accuracy": 95, "description": "전류가 흐르는 이빨로 문다.", "effect": {"type": "status", "status": "paralysis", "target": "enemy"}, "effect_chance": 10}
MOVE_DATA[224] = {"name": "전기자석파", "type": "electric", "category": "status", "power": 0, "accuracy": 90, "description": "약학 전기로 마비시킨다.", "effect": {"type": "status", "status": "paralysis", "target": "enemy"}, "effect_chance": 100}

# Grass
MOVE_DATA[231] = {"name": "덩굴채찍", "type": "grass", "category": "physical", "power": 45, "accuracy": 100, "description": "덩굴로 후려친다.", "effect": None, "effect_chance": 0}
MOVE_DATA[232] = {"name": "에너지볼", "type": "grass", "category": "special", "power": 90, "accuracy": 100, "description": "자연의 힘을 모아 발사한다.", "effect": {"type": "stat_change", "stat": "defense", "value": -1, "target": "enemy"}, "effect_chance": 10}

# Fighting/Ground/Rock
MOVE_DATA[241] = {"name": "인파이트", "type": "fighting", "category": "physical", "power": 120, "accuracy": 100, "description": "방어를 포기하고 맹공격한다.", "effect": {"type": "stat_change", "stat": "defense", "value": -1, "target": "self"}, "effect_chance": 100}
MOVE_DATA[242] = {"name": "지진", "type": "ground", "category": "physical", "power": 100, "accuracy": 100, "description": "땅을 흔들어 공격한다.", "effect": None, "effect_chance": 0}
MOVE_DATA[243] = {"name": "스톤샤워", "type": "rock", "category": "physical", "power": 75, "accuracy": 90, "description": "바위를 떨어뜨린다. (풀죽음)", "effect": {"type": "status", "status": "flinch", "target": "enemy"}, "effect_chance": 30}

# Strategic Status Matches
MOVE_DATA[251] = {"name": "칼춤", "type": "normal", "category": "status", "power": 0, "accuracy": 100, "description": "전투 춤을 추어 공격력을 크게 올린다.", "effect": {"type": "stat_change", "stat": "strength", "value": 2, "target": "self"}, "effect_chance": 100}
MOVE_DATA[252] = {"name": "명상", "type": "psychic", "category": "status", "power": 0, "accuracy": 100, "description": "정신을 통일하여 특수공격(지능)을 올린다.", "effect": {"type": "stat_change", "stat": "intelligence", "value": 1, "target": "self"}, "effect_chance": 100}
MOVE_DATA[253] = {"name": "방어", "type": "normal", "category": "status", "power": 0, "accuracy": 100, "description": "이번 턴 공격을 막는다. (우선도 높음)", "priority": 4, "effect": {"type": "status", "status": "protect", "target": "self"}, "effect_chance": 100}

# Update Learnsets
# Spread new moves somewhat randomly/thematically for testing
PET_LEARNSET["dog"].update({1: [1, 2, 6], 3: [203, 223], 5: [3, 4, 104], 10: [5, 241, 242]})
PET_LEARNSET["cat"].update({1: [101, 102], 3: [103, 204], 5: [104, 252], 10: [105, 202, 222]})

# 10. [New] PP Default Injection (Monkey Patching for Safety/Convenience)
for mid, mdata in MOVE_DATA.items():
    if "max_pp" not in mdata:
        # Default PP based on Power
        p = mdata.get("power", 0)
        if p >= 120: mdata["max_pp"] = 5
        elif p >= 90: mdata["max_pp"] = 10
        elif p >= 60: mdata["max_pp"] = 15
        else: mdata["max_pp"] = 20 # Low power or status moves
        
    # Ensure immune key exists in ALL generic dictionary entries if referenced blindly (Optional, mostly handled in code .get)