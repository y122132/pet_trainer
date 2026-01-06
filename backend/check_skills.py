import sys
import os

# App Path Setup
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.game.battle_manager import BattleManager, BattleState
from app.game.game_assets import MOVE_DATA, STATUS_DATA

# Mocks
class MockStat:
    def __init__(self, s=10, i=10, d=10, a=10, l=10):
        self.strength = s
        self.intelligence = i
        self.defense = d
        self.agility = a
        self.luck = l

def print_log(logs):
    if not logs: return
    if isinstance(logs, list):
        for l in logs:
            if isinstance(l, dict):
                 print(f"[{l.get('type')}] {l.get('message')}")
            else:
                print(l)
    else:
        print(logs)

def test_bleed():
    print("\n--- Test Bleed (Lv25 출혈 이빨) ---")
    atk_state = BattleState(100, 100)
    def_state = BattleState(100, 100)
    atk_stat = MockStat()
    def_stat = MockStat()

    # Apply Move 25 (Bleed)
    print("User uses Lv25 출혈 이빨...")
    logs = BattleManager.apply_move_effects(25, atk_state, def_state, atk_stat, "User", "Enemy")
    print_log(logs)

    if def_state.status_ailment == "bleed":
        print("PASS: Enemy is bleeding.")
    else:
        print(f"FAIL: Enemy status is {def_state.status_ailment}")

    # Sim Turn End
    print("End of Turn (Enemy)...")
    dmg, msg, detail = BattleManager.process_status_effects(def_stat, def_state)
    print(f"Bleed Damage: {dmg}")
    print(f"Message: {msg}")
    
    if dmg > 0 and "출혈" in msg:
        print("PASS: Bleed damage applied.")
    else:
        print("FAIL: Bleed damage not applied.")

def test_fear():
    print("\n--- Test Fear (Lv75 지배의 포효) ---")
    atk_state = BattleState(100, 100)
    def_state = BattleState(100, 100)
    atk_stat = MockStat()
    def_stat = MockStat()

    # Apply Move 75 (Fear)
    print("User uses Lv75 지배의 포효...")
    logs = BattleManager.apply_move_effects(75, atk_state, def_state, atk_stat, "User", "Enemy")
    print_log(logs)

    if def_state.status_ailment == "fear":
        print("PASS: Enemy is feared.")
    else:
        print(f"FAIL: Enemy status is {def_state.status_ailment}")

    # Check Can Move (Loop 100 times to check approx 50%)
    cant_move_count = 0
    for _ in range(100):
        can, msg, _ = BattleManager.can_move(def_state)
        if not can and "공포" in msg:
            cant_move_count += 1
    
    print(f"Fear Proc Rate (Expected ~50): {cant_move_count}%")
    if 30 < cant_move_count < 70:
        print("PASS: Fear rate reasonable.")
    else:
        print("FAIL: Fear rate abnormal.")

def test_scaling():
    print("\n--- Test HP Scaling (Lv50 본능 각성) ---")
    atk_state = BattleState(100, 100) # Full HP
    def_state = BattleState(100, 100)
    atk_stat = MockStat(s=50) # High Str
    def_stat = MockStat(d=10) # Low Def
    
    # 1. Full HP Damage
    dmg_full, _, _ = BattleManager.calculate_damage(atk_stat, atk_state, def_stat, def_state, 50)
    print(f"Damage at 100% HP: {dmg_full}")

    # 2. Low HP Damage
    atk_state.current_hp = 10 # 10% HP
    dmg_low, _, _ = BattleManager.calculate_damage(atk_stat, atk_state, def_stat, def_state, 50)
    print(f"Damage at 10% HP: {dmg_low}")

    if dmg_low > dmg_full * 1.5:
        print("PASS: Low HP damage significantly higher.")
    else:
        print("FAIL: Scaling weak or not working.")

if __name__ == "__main__":
    test_bleed()
    test_fear()
    test_scaling()
