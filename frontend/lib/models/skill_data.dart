// 기술 데이터 (백엔드 game_assets.py와 동기화 필요)
const Map<int, Map<String, dynamic>> SKILL_DATA = {
  1: {"name": "짖기", "power": 20, "accuracy": 100, "type": "normal", "description": "큰 소리로 짖어 상대를 놀라게 한다."},
  2: {"name": "버티기", "power": 0, "accuracy": 100, "type": "normal", "description": "공격을 버텨내며 방어력을 높인다."},
  3: {"name": "회복 본능", "power": 0, "accuracy": 100, "type": "heal", "description": "체력을 약간 회복한다."},
  4: {"name": "꼬리 살랑", "power": 0, "accuracy": 100, "type": "normal", "description": "방심하게 만들어 상대의 방어력을 낮춘다."},
  5: {"name": "간식 발견", "power": 40, "accuracy": 90, "type": "normal", "description": "간식을 발견한 기쁨으로 돌진한다."},
  
  101: {"name": "할퀴기", "power": 35, "accuracy": 95, "type": "normal", "description": "날카로운 발톱으로 상대를 할퀸다."},
  102: {"name": "냥점프", "power": 0, "accuracy": 100, "type": "evade", "description": "높이 점프하여 회피율을 높인다."},
  103: {"name": "신경 긁기", "power": 15, "accuracy": 100, "type": "psychic", "description": "상대의 신경을 긁어 공격력을 낮춘다."},
  104: {"name": "급습", "power": 40, "accuracy": 100, "type": "dark", "description": "보이지 않는 곳에서 기습한다."},
  105: {"name": "냥냥펀치", "power": 15, "accuracy": 90, "type": "fighting", "description": "빠르게 연속으로 펀치를 날린다."}
};
