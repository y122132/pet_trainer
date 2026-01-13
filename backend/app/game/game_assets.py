# 1. Skill_Database: 각 스킬의 상세 데이터
MOVE_DATA = {
    # --- 공통 / 강아지 계열 (Dog) ---
    # Lv5 경계 태세 (Dog)
    5: {
        "name": "경계 태세", 
        "power": 0, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "status",
        "description": "자세를 낮추고 경계하여 회피율을 높인다.",
        "effect": {"type": "stat_change", "stat": "evasion", "value": 2, "target": "self"},
        "effect_chance": 100,
        "max_pp": 20
    },
    # Lv10 위협의 포효 (Dog)
    10: {
        "name": "위협의 포효", 
        "power": 0, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "status",
        "description": "거칠게 포효하여 상대의 기를 꺽어 공격력을 낮춘다.",
        "effect": {"type": "stat_change", "stat": "strength", "value": -1, "target": "enemy"},
        "effect_chance": 100,
        "max_pp": 20
    },
    # Lv15 사냥 개시 (Dog)
    15: {
        "name": "사냥 개시", 
        "power": 60, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "physical",
        "priority": 2, 
        "description": "누구보다 빠르게 먼저 공격한다. 사냥의 시작을 알린다.",
        "effect": None,
        "effect_chance": 0,
        "max_pp": 15
    },
    # Lv25 출혈 이빨 (Dog)
    25: {
        "name": "출혈 이빨", 
        "power": 50, 
        "accuracy": 95, 
        "type": "normal", 
        "category": "physical",
        "description": "상대를 물어뜯어 출혈을 일으킨다.",
        "effect": {"type": "status", "status": "bleed", "target": "enemy"},
        "effect_chance": 100, 
        "max_pp": 15
    },
    # Lv30 야성 폭주 (Dog - Ult)
    30: {
        "name": "야성 폭주", 
        "power": 0, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "status",
        "description": "야성을 폭발시켜 방어를 포기하고 공격력을 대폭 올린다.",
        "effect": [
            {"type": "stat_change", "stat": "strength", "value": 3, "target": "self"},
            {"type": "stat_change", "stat": "defense", "value": -2, "target": "self"}
        ],
        "effect_chance": 100,
        "max_pp": 5
    },
    
    # --- 고양이 계열 (Cat) ---
    # Lv5 그루밍 (Cat)
    105: {
        "name": "그루밍", 
        "power": 0, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "status",
        "description": "털을 고르며 마음을 진정시킨다. (회복 + 상태이상 제거)",
        "effect": {"type": "heal", "value": 20, "target": "self"}, # Simplification
        "effect_chance": 100,
        "max_pp": 15
    },
    # Lv10 냥냥 펀치 (Cat)
    110: {
        "name": "냥냥 펀치", 
        "power": 40, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "physical",
        "priority": 1, 
        "description": "빠르게 앞발로 때린다. 선공 확률이 있다.",
        "effect": None,
        "effect_chance": 0,
        "max_pp": 25
    },
    # Lv15 살금살금 (Cat)
    115: {
        "name": "살금살금", 
        "power": 0, 
        "accuracy": 100, 
        "type": "dark", 
        "category": "status",
        "description": "기척을 숨겨 회피율을 크게 높인다.",
        "effect": {"type": "stat_change", "stat": "evasion", "value": 2, "target": "self"},
        "effect_chance": 100,
        "max_pp": 10
    },
    # Lv25 할퀴기 (Cat)
    125: {
        "name": "할퀴기", 
        "power": 55, 
        "accuracy": 95, 
        "type": "normal", 
        "category": "physical",
        "description": "날카로운 발톱으로 할퀸다. (출혈 확률)",
        "effect": {"type": "status", "status": "bleed", "target": "enemy"},
        "effect_chance": 50, 
        "max_pp": 15
    },
    # Lv30 야옹이의 분노 (Cat - Ult)
    130: {
        "name": "야옹이의 분노", 
        "power": 90, 
        "accuracy": 90, 
        "type": "dark", 
        "category": "physical",
        "description": "화난 고양이의 무서움을 보여준다. 치명타 확률이 높다.",
        "effect": {"type": "stat_change", "stat": "crit_rate", "value": 2, "target": "self"}, # Crit boost before hit logic needed? Or just high crit move
        "effect_chance": 100,
        "max_pp": 5
    },

    # --- 새 계열 (Bird) ---
    # Lv5 쪼기 (Bird)
    205: {
        "name": "쪼기", 
        "power": 40, 
        "accuracy": 100, 
        "type": "flying", 
        "category": "physical",
        "description": "부리로 콕콕 쪼아 공격한다.",
        "effect": None,
        "effect_chance": 0,
        "max_pp": 35
    },
    # Lv10 날개치기 (Bird)
    210: {
        "name": "날개치기", 
        "power": 0, 
        "accuracy": 95, 
        "type": "flying", 
        "category": "status",
        "description": "날개를 퍼덕여 모래바람을 일으켜 상대 명중률을 낮춘다.",
        "effect": {"type": "stat_change", "stat": "accuracy", "value": -1, "target": "enemy"},
        "effect_chance": 100,
        "max_pp": 20
    },
    # Lv15 순풍 (Bird)
    215: {
        "name": "순풍", 
        "power": 0, 
        "accuracy": 100, 
        "type": "flying", 
        "category": "status",
        "description": "바람을 타고 속도를 높인다.",
        "effect": {"type": "stat_change", "stat": "agility", "value": 2, "target": "self"},
        "effect_chance": 100,
        "max_pp": 15
    },
    # Lv25 공중제비 (Bird)
    225: {
        "name": "공중제비", 
        "power": 60, 
        "accuracy": 100, 
        "type": "flying", 
        "category": "physical",
        "description": "빠르게 공중을 돌아 상대의 허를 찌른다. (반드시 명중)",
        "effect": None, # Aerial Ace logic
        "effect_chance": 0, 
        "max_pp": 20
    },
    # Lv30 폭풍우 (Bird - Ult)
    230: {
        "name": "폭풍우", 
        "power": 110, 
        "accuracy": 70, 
        "type": "flying", 
        "category": "special",
        "description": "거대한 폭풍을 일으킨다. 명중률은 낮지만 강력하다.",
        "effect": {"type": "status", "status": "confusion", "target": "enemy"},
        "effect_chance": 30,
        "max_pp": 5
    },


    # --- High Level Shared / Unique (Originals shifted or kept) ---
    45: {
        "name": "전투 감각", 
        "power": 0, 
        "accuracy": 100, 
        "type": "psychic", 
        "category": "status",
        "description": "전투 흐름을 읽어 명중률과 치명타율을 높인다.",
        "effect": [
            {"type": "stat_change", "stat": "accuracy", "value": 1, "target": "self"},
            {"type": "stat_change", "stat": "crit_rate", "value": 1, "target": "self"}
        ],
        "effect_chance": 100,
        "max_pp": 10
    },
    # Lv50 본능 각성: 궁극 
    50: {
        "name": "본능 각성", 
        "power": 70, 
        "accuracy": 100, 
        "type": "fighting", 
        "category": "physical",
        "scaling": "hp_loss", 
        "description": "위기에 몰릴수록 더 강력한 힘을 발휘한다.",
        "effect": None,
        "effect_chance": 0,
        "max_pp": 5
    },
    # Lv65 집중
    65: {
        "name": "집중", 
        "power": 0, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "status",
        "description": "정신을 집중하여 급소를 노릴 확률을 높인다.",
        "effect": {"type": "stat_change", "stat": "crit_rate", "value": 2, "target": "self"},
        "effect_chance": 100,
        "max_pp": 15
    },
    # Lv75 지배의 포효
    75: {
        "name": "지배의 포효", 
        "power": 0, 
        "accuracy": 90, 
        "type": "dark", 
        "category": "status",
        "description": "압도적인 존재감으로 상대를 공포에 질리게 한다.",
        "effect": {"type": "status", "status": "fear", "target": "enemy"},
        "effect_chance": 100,
        "max_pp": 5
    },
    # Lv90 전투의 정점
    90: {
        "name": "전투의 정점", 
        "power": 0, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "status",
        "description": "수많은 전투 경험으로 모든 능력을 끌어올린다.",
        "effect": [
            {"type": "stat_change", "stat": "strength", "value": 1, "target": "self"},
            {"type": "stat_change", "stat": "defense", "value": 1, "target": "self"},
            {"type": "stat_change", "stat": "agility", "value": 1, "target": "self"},
            {"type": "stat_change", "stat": "intelligence", "value": 1, "target": "self"}
        ],
        "effect_chance": 100,
        "max_pp": 5
    },
    # Lv100 야수의 왕
    100: {
        "name": "야수의 왕", 
        "power": 150, 
        "accuracy": 100, 
        "type": "dragon",
        "category": "physical",
        "description": "짐승의 왕으로서 모든 것을 짓밟는다.",
        "effect": [
            {"type": "stat_change", "stat": "strength", "value": 2, "target": "self"},
            {"type": "stat_change", "stat": "defense", "value": -2, "target": "enemy"}
        ],
        "effect_chance": 100,
        "max_pp": 1
    }
}

# 2. Type_Chart: 속성 상성 (공격 타입 기준)
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

# 3. PET_LEARNSET: 펫 종류에 따른 기술 습득 테이블
# Shared High Level Skills (35+)
SHARED_HIGH_LEVEL = {
    35: [45],
    45: [50],
    55: [65],
    65: [75],
    80: [90],
    95: [100]
}

DOG_LEARNSET = {
    5: [5],
    8: [10],
    12: [15],
    18: [25],
    25: [30],
    **SHARED_HIGH_LEVEL
}

CAT_LEARNSET = {
    5: [105],
    8: [110],
    12: [115],
    18: [125],
    25: [130],
    **SHARED_HIGH_LEVEL
}

BIRD_LEARNSET = {
    5: [205],
    8: [210],
    12: [215],
    18: [225],
    25: [230],
    **SHARED_HIGH_LEVEL
}

PET_LEARNSET = {
    "dog": DOG_LEARNSET,
    "cat": CAT_LEARNSET,
    "bird": BIRD_LEARNSET,
    # Fallbacks or unfinished types
    "bear": DOG_LEARNSET,
    "robot": DOG_LEARNSET
}

PET_TYPE_MAP = {
    "dog": "normal",
    "cat": "normal",
    "bear": "earth",
    "bird": "wind",
    "dragon": "fire",
    "fish": "water"
}


# 4. Status Effects Info (Updated)
STATUS_DATA = {
    # Persistent (Ailment)
    "poison": {"name": "독", "desc": "매 턴 체력의 1/8 피해", "min_turn": 3, "max_turn": 6},
    "paralysis": {"name": "마비", "desc": "스피드 저하 및 25% 확률로 행동 불가", "min_turn": 2, "max_turn": 5},
    "burn": {"name": "화상", "desc": "매 턴 체력 피해 및 공격력 반감", "min_turn": 3, "max_turn": 6},
    
    # New
    "bleed": {"name": "출혈", "desc": "지속적으로 체력이 빠져나간다 (1/8)", "min_turn": 2, "max_turn": 4},
    "fear": {"name": "공포", "desc": "50% 확률로 아무것도 하지 못한다", "min_turn": 2, "max_turn": 4},

    # Volatile
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

# 6. Type Immunity Update
TYPE_CHART["ground"]["immune"] = ["flying"]
TYPE_CHART["normal"]["immune"] = ["ghost"]
TYPE_CHART["electric"]["immune"] = ["ground"]
TYPE_CHART["psychic"]["immune"] = ["dark"]
TYPE_CHART["poison"]["immune"] = ["steel"]
TYPE_CHART["dragon"]["immune"] = ["fairy"]
TYPE_CHART["fighting"]["immune"] = ["ghost"]

# 7. Field & Weather Modifiers
FIELD_EFECTS = {
    "weather": {
        "sun": {"fire": 1.5, "water": 0.5, "name": "쾌청"},
        "rain": {"water": 1.5, "fire": 0.5, "name": "비"},
        "clear": {"name": "맑음"}
    },
    "location": {
        "stadium": {"name": "경기장"}, 
        "cave": {"rock": 1.2, "ground": 1.2, "name": "동굴"},
        "forest": {"grass": 1.2, "bug": 1.2, "name": "숲"},
        "water": {"water": 1.2, "name": "물가"}
    }
}

# 8. Species Base Stats (종족값)
PET_BASE_STATS = {
    "dog": {"strength": 10, "intelligence": 10, "defense": 10, "agility": 10, "luck": 10}, 
    "cat": {"strength": 9, "intelligence": 12, "defense": 8, "agility": 14, "luck": 12},  
    "bird": {"strength": 9, "intelligence": 9, "defense": 8, "agility": 15, "luck": 10},  
    "bear": {"strength": 15, "intelligence": 5, "defense": 14, "agility": 6, "luck": 10}, 
    "robot": {"strength": 12, "intelligence": 12, "defense": 12, "agility": 8, "luck": 10} 
}