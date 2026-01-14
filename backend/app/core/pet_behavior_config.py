
"""
반려동물 행동 설정 (Pet Behavior Configuration)
각 반려동물의 YOLO Class ID와 해당 모드별 상호작용 대상(Target), 메시지 등을 정의합니다.
이 파일을 수정하여 새로운 동물을 쉽게 추가할 수 있습니다.
"""

# YOLO COCO Class ID 참조 (주요 물체 ID)
# 0: 사람 (person)
# 16: 강아지 (dog)
# 15: 고양이 (cat)
# 29: 프리스비/원반 (frisbee)
# 32: 스포츠 공 (sports ball)
# 39: 병 (bottle)
# 41: 컵 (cup)
# 45: 그릇 (bowl)
# 46: 바나나 (banana)
# 47: 사과 (apple)
# 48: 샌드위치 (sandwich)
# 49: 오렌지 (orange)
# 50: 브로콜리 (broccoli)
# 51: 당근 (carrot)

PET_BEHAVIORS = {
    # --- DOG (강아지 - ID: 16) ---
    16: {
        "playing": {
            # 32:공, 29:원반, 28:가방(장난감대용?), 39:병(페트병놀이), 41:컵(종이컵놀이)
            "targets": [32, 29, 39, 41], 
            "success_msg": "공놀이 중! 🎾",
            "fail_msg": "장난감(공, 인형)을 보여주세요",
            "feedback_success": "반려동물이 즐거워해요!", # AI 페르소나 피드백 키워드
            "feedback_fail": "toy_missing"
        },
        "feeding": {
            # 45:그릇, 41:컵, 39:병, 46~51:과일/채소
            "targets": [45, 41, 39, 46, 47, 48, 49, 50, 51], 
            "success_msg": "맛있는 식사 시간 🥣",
            "fail_msg": "그릇이나 간식을 보여주세요",
            "feedback_success": "건강해지고 있어요!",
            "feedback_fail": "food_missing"
        },
        "interaction": {
            "targets": [0], # 대상 물체: 사람
            "success_msg": "주인과 교감 중 ❤️",
            "fail_msg": "반려동물과 함께 찍어주세요",
            "feedback_success": "행복도가 올라갑니다!",
            "feedback_fail": "owner_missing"
        }
    },
    
    # --- CAT (고양이 - ID: 15) ---
    15: {
        "playing": {
            "targets": [39, 41, 29], # 고양이는 병이나 컵, 원반 등 다양한 물체에 반응
            "success_msg": "사냥 놀이 중! 🎣",
            "fail_msg": "장난감을 보여주세요",
            "feedback_success": "냥냥펀치 날리기 직전!",
            "feedback_fail": "toy_missing"
        },
        "feeding": {
            "targets": [45, 41], # 그릇, 컵 (우유 등)
            "success_msg": "냠냠 쩝쩝 🐟",
            "fail_msg": "밥그릇을 보여주세요",
            "feedback_success": "골골송 부르는 중...",
            "feedback_fail": "food_missing"
        },
        "interaction": {
            "targets": [0], # 사람 (집사)
            "success_msg": "집사와 함께 📸",
            "fail_msg": "집사님 어디 계세요?",
            "feedback_success": "그루밍 해주는 중?",
            "feedback_fail": "owner_missing"
        }
    },

    # --- BIRD (새 - ID: 14) ---
    14: {
        "playing": {
            "targets": [32, 39, 41, 29], # 공, 병, 컵, 원반
            "success_msg": "새가 날아다녀요! 🦜",
            "fail_msg": "장난감을 보여주세요",
            "feedback_success": "날개를 파닥입니다!",
            "feedback_fail": "toy_missing"
        },
        "feeding": {
            "targets": [45, 41], # 그릇, 컵
            "success_msg": "모이 쪼는 중 🐦",
            "fail_msg": "모이통이나 물을 주세요",
            "feedback_success": "기분이 좋아보여요!",
            "feedback_fail": "food_missing"
        },
        "interaction": {
            "targets": [0], # 사람
            "success_msg": "손에 올라왔어요! 📸",
            "fail_msg": "새와 함께 있어주세요",
            "feedback_success": "어깨에 앉으려 합니다!",
            "feedback_fail": "owner_missing"
        }
    }
}

# 기본 행동 설정 (알 수 없는 동물이 감지되었을 때 강아지 로직 사용)
DEFAULT_BEHAVIOR = PET_BEHAVIORS[16]

# [NEW] 탐지 민감도 및 판정 로직 설정
DETECTION_SETTINGS = {
    # 1. 신뢰도 임계값 (Confidence Threshold)
    "logic_conf": {
        "easy": 0.25,
        "hard": 0.6
    },
    
    # 2. 상호작용 거리 임계값 (Min Distance for Interaction)
    # 화면 대각선 기준 비율 (0.0 ~ 1.0)
    "min_distance": {
        "playing": { "easy": 0.25, "hard": 0.15 },
        "feeding": { "easy": 0.15, "hard": 0.10 },
        "interaction": { "easy": 0.30, "hard": 0.20 }
    },
    
    # 3. 겹침 비율 임계값 (Overlap Ratio for Feeding)
    "max_overlap": {
        "easy": 0.1,    # 살짝 겹쳐도 인정
        "hard": 0.3     # 많이 겹쳐야 인정
    }
}
