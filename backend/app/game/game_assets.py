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
        "description": "큰 소리로 짖어 상대를 놀라게 한다.",
        "effect": {"type": "stat_change", "stat": "defense", "value": -1, "target": "enemy"},
        "effect_chance": 30
    },
    2: {
        "name": "버티기", 
        "power": 0, 
        "accuracy": 100, 
        "type": "normal", 
        "description": "공격을 버텨내며 방어력을 높인다.",
        "effect": {"type": "stat_change", "stat": "defense", "value": 1, "target": "self"},
        "effect_chance": 100
    },
    3: {
        "name": "회복 본능", 
        "power": 0, 
        "accuracy": 100, 
        "type": "heal", 
        "description": "체력을 약간 회복한다.",
        "effect": {"type": "heal", "value": 20, "target": "self"}, # value는 % 또는 고정값 (구현 나름)
        "effect_chance": 100
    },
    4: {
        "name": "꼬리 살랑", 
        "power": 0, 
        "accuracy": 100, 
        "type": "normal", 
        "description": "방심하게 만들어 상대의 방어력을 낮춘다.",
        "effect": {"type": "stat_change", "stat": "defense", "value": -1, "target": "enemy"},
        "effect_chance": 100
    },
    5: {
        "name": "간식 발견", 
        "power": 40, 
        "accuracy": 90, 
        "type": "normal", 
        "description": "간식을 발견한 기쁨으로 돌진한다.",
        "effect": {"type": "stat_change", "stat": "strength", "value": 1, "target": "self"},
        "effect_chance": 50
    },
    
    101: {
        "name": "할퀴기", 
        "power": 35, 
        "accuracy": 95, 
        "type": "normal", 
        "description": "날카로운 발톱으로 상대를 할퀸다. (확률적 출혈/독)",
        "effect": {"type": "status", "status": "poison", "target": "enemy"},
        "effect_chance": 30
    },
    102: {
        "name": "냥점프", 
        "power": 0, 
        "accuracy": 100, 
        "type": "evade", 
        "description": "높이 점프하여 회피율(민첩성)을 높인다.",
        "effect": {"type": "stat_change", "stat": "agility", "value": 1, "target": "self"},
        "effect_chance": 100
    },
    103: {
        "name": "신경 긁기", 
        "power": 15, 
        "accuracy": 100, 
        "type": "psychic", 
        "description": "상대의 신경을 긁어 공격력을 낮춘다.",
        "effect": {"type": "stat_change", "stat": "strength", "value": -1, "target": "enemy"},
        "effect_chance": 100
    },
    104: {
        "name": "급습", 
        "power": 40, 
        "accuracy": 100, 
        "type": "dark", 
        "description": "보이지 않는 곳에서 기습한다. (높은 크리티컬/마비)",
        "effect": {"type": "status", "status": "paralysis", "target": "enemy"},
        "effect_chance": 10
    },
    105: {
        "name": "냥냥펀치", 
        "power": 15, 
        "accuracy": 90, 
        "type": "fighting", 
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

# 3. PET_LEARNSET: 펫 종류에 따른 기술 습득 테이블
PET_LEARNSET = {
    "dog": {
        1: [1, 2],       # 짖기, 버티기
        5: [3, 4],       # 회복 본능, 꼬리 살랑
        10: [5]          # 간식 발견
    },
    "cat": {
        1: [101, 102],   # 할퀴기, 냥점프
        5: [103, 104],   # 신경 긁기, 급습
        10: [105]        # 냥냥펀치
    }
}

# 4. Status Effects Info
STATUS_DATA = {
    "poison": {"name": "독", "desc": "매 턴 체력의 1/8 피해", "min_turn": 3, "max_turn": 6},
    "paralysis": {"name": "마비", "desc": "스피드 저하 및 25% 확률로 행동 불가", "min_turn": 2, "max_turn": 5},
    "burn": {"name": "화상", "desc": "매 턴 체력 피해 및 공격력 반감", "min_turn": 3, "max_turn": 6},
    "confusion": {"name": "혼란", "desc": "33% 확률로 자해 데미지 (1~4턴 지속)", "min_turn": 1, "max_turn": 4}
}

# 5. Stat Stages Multiplier (-6 to +6)
STAT_STAGES = {
    -6: 2/8, -5: 2/7, -4: 2/6, -3: 2/5, -2: 2/4, -1: 2/3,
    0: 1.0,
    1: 3/2, 2: 4/2, 3: 5/2, 4: 6/2, 5: 7/2, 6: 8/2
}