# --- 게임 에셋 (Game Assets) ---
# 이 파일은 배틀 시스템에서 사용하는 모든 정적 데이터(스킬, 속성, 종족값 등)를 정의합니다.
# 팀원들이 쉽게 컨텐츠를 확장할 수 있도록 가이드를 참고하세요.

# ==========================================
# [GUIDE] 새로운 스킬 추가하는 법 (How to add a new Move)
# ==========================================
# 1. MOVE_DATA 딕셔너리에 새로운 ID를 키(Key)로 추가합니다. (예: 301)
# 2. 다음 필드들을 정의합니다:
#    - name (str): 스킬 이름 (UI 표시용)
#    - type (str): 스킬 속성 ('fire', 'water', 'grass', 'normal' 등)
#    - category (str): 데미지 분류 ('physical': 힘vs방어, 'special': 지능vs지능, 'status': 변화기)
#    - power (int): 스킬 위력 (0이면 데미지 없음. 보통 40~120 사이)
#    - accuracy (int): 명중률 (0~100). 100은 빗나갈 수 있음. 999는 필중.
#    - description (str): 스킬 설명 (UI 표시용)
#    - effect (dict, optional): 부가 효과 정의
#      - type: 'stat_change' (스탯 변화), 'status' (상태 이상 부여), 'heal' (회복), 'field_change' (날씨 등)
#      - target: 'self' (자신), 'enemy' (상대), 'room' (필드)
#      - stat/status/field: 변경할 대상 속성
#      - value: 변경할 값 (스탯은 랭크, 힐은 퍼센트 등)
#    - effect_chance (int): 부가 효과 발동 확률 (0~100)
#
# [예시]
# 999: {
#     "name": "초강력 펀치",
#     "type": "fighting",
#     "category": "physical",
#     "power": 100,
#     "accuracy": 80,
#     "description": "강력하지만 빗나갈 수 있는 펀치",
#     "effect": {"type": "status", "status": "paralysis", "target": "enemy"},
#     "effect_chance": 30 # 30% 확률로 마비
# }
# ==========================================

# 1. Skill_Database: 각 스킬의 상세 데이터
MOVE_DATA = {
    # Lv5 경계 태세: 일반 / 회피율 증가 (2턴) -> Stat Change Agility? or Evasion? 
    # Use Evasion for "Dodge". 
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

    # Lv10 위협의 포효: 일반 / 상대 공격력 감소 (2턴)
    10: {
        "name": "위협의 포효", 
        "power": 0, 
        "accuracy": 100, 
        "type": "normal", # Sound?
        "category": "status",
        "description": "거칠게 포효하여 상대의 기를 꺽어 공격력을 낮춘다.",
        "effect": {"type": "stat_change", "stat": "strength", "value": -1, "target": "enemy"},
        "effect_chance": 100,
        "max_pp": 20
    },

    # Lv15 사냥 개시: 준궁 / 선공 확정 + 첫 공격 피해 증가
    # Priority move with high power. "First attack damage boost" logic is hard to inject perfectly without "turn count" state.
    # Instead, we make it a High Priority + Decent Power move, conceptualizing "Initiative".
    15: {
        "name": "사냥 개시", 
        "power": 60, 
        "accuracy": 100, 
        "type": "normal", 
        "category": "physical",
        "priority": 2, # High Priority
        "description": "누구보다 빠르게 먼저 공격한다. 사냥의 시작을 알린다.",
        "effect": None,
        "effect_chance": 0,
        "max_pp": 15
    },

    # Lv25 출혈 이빨: 일반 / 공격 + 출혈 (2턴)
    25: {
        "name": "출혈 이빨", 
        "power": 50, 
        "accuracy": 95, 
        "type": "normal", 
        "category": "physical",
        "description": "상대를 물어뜯어 출혈을 일으킨다.",
        "effect": {"type": "status", "status": "bleed", "target": "enemy"},
        "effect_chance": 100, # Guaranteed bleed? or chance? User said "+ Bleed", implying guarantee.
        "max_pp": 15
    },

    # Lv30 야성 폭주: 궁극 / 공격력 대폭 증가 / 방어 감소
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

    # Lv45 전투 감각: 일반 / 상태이상 성공률 증가 (Implemented as Crit Rate increase as "Sense" is vague for status chance mod in current architecture)
    # User said "Status Success Rate Increase". We don't have "Status Accumulation" or "Accuracy for Status" separate stat easily.
    # Alternative: Increase Accuracy & Crit (Vital spots).
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

    # Lv50 본능 각성: 궁극 / HP 낮을수록 능력(Damage) 급상승
    # Requires Special Logic in Calculator
    50: {
        "name": "본능 각성", 
        "power": 70, # Base power
        "accuracy": 100, 
        "type": "fighting", 
        "category": "physical",
        "scaling": "hp_loss", # Custom Flag handled in calculator
        "description": "위기에 몰릴수록 더 강력한 힘을 발휘한다.",
        "effect": None,
        "effect_chance": 0,
        "max_pp": 5
    },

    # Lv65 집중: 일반 / 치명타 확률 증가
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

    # Lv75 지배의 포효: 궁극 / 공포 -> 행동 실패 확률 증가
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

    # Lv90 전투의 정점: 일반 / 모든 능력 소폭 증가
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

    # Lv100 야수의 왕: 최종 궁극 / 자신 강화 + 상대 약화
    100: {
        "name": "야수의 왕", 
        "power": 150, 
        "accuracy": 100, 
        "type": "dragon", # Majestic type
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
# All pets learn the same new set for now as requested "Replace Everything"
# Mapping Level -> List of Move IDs
COMMON_LEARNSET = {
    5: [5],
    10: [10],
    15: [15],
    25: [25],
    30: [30],
    45: [45],
    50: [50],
    65: [65],
    75: [75],
    90: [90],
    100: [100]
}

PET_LEARNSET = {
    "dog": COMMON_LEARNSET,
    "cat": COMMON_LEARNSET,
    "bird": COMMON_LEARNSET,
    "bear": COMMON_LEARNSET,
    "robot": COMMON_LEARNSET
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