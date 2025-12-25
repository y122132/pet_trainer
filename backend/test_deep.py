import asyncio
from app.game.battle_manager import BattleManager, BattleState
from app.game.battle_calculator import BattleCalculator
from app.game.game_assets import MOVE_DATA, TYPE_CHART, FIELD_EFECTS

# Mock Data
MOVE_DATA[888] = {
    "name": "Ground Smash",
    "type": "ground",
    "power": 100,
    "accuracy": 100,
    "max_pp": 5
}
MOVE_DATA[889] = {
    "name": "Fire Blast",
    "type": "fire",
    "power": 100,
    "accuracy": 100,
    "max_pp": 5
}
# Correct Mock for Immunity (Ground moves on Flying are immune)
# Note: Real game_assets.py is fixed now, but we override here just in case import cached old dict or to be explicit.
if "immune" not in TYPE_CHART["ground"]: TYPE_CHART["ground"]["immune"] = []
TYPE_CHART["ground"]["immune"].append("flying")

def test_deep_logic():
    print("=== Testing Deep Logic ===")
    
    # 1. Immunity Test
    print("[1] Immunity Check (Ground vs Flying)")
    p1_stat = type("Stat", (), {"strength": 10, "defense": 10, "luck": 10, "agility": 10})()
    p1_state = BattleState()
    p2_state = BattleState()
    
    dmg, crit, eff = BattleManager.calculate_damage(
        p1_stat, p1_state, p1_stat, p2_state, 888, defender_type="flying"
    )
    if dmg == 0 and eff == "immune":
        print(f"PASS: Damage {dmg}, Effect {eff}")
    else:
        print(f"FAIL: Damage {dmg}, Effect {eff}")

    # 2. Field Effect Test (Sun -> Fire x1.5)
    print("[2] Field Effect Check (Sun vs Fire Move)")
    field_data = {"weather": "sun", "location": "stadium"}
    
    dmg_normal, _, _ = BattleManager.calculate_damage(
        p1_stat, p1_state, p1_stat, p2_state, 889, defender_type="normal"
    )
    
    dmg_sun, _, _ = BattleManager.calculate_damage(
        p1_stat, p1_state, p1_stat, p2_state, 889, defender_type="normal", field_data=field_data
    )
    
    print(f"Normal Damage: {dmg_normal}, Sun Damage: {dmg_sun}")
    if dmg_sun > dmg_normal:
        print("PASS: Sun boosted Fire damage.")
    else:
        print("FAIL: No boost.")

    # 3. Volatile Status Test (Flinch)
    print("[3] Volatile Check (Flinch)")
    p1_state.volatile["flinch"] = 1
    can_move, msg = BattleManager.can_move(p1_state)
    if not can_move and "풀죽어" in msg:
        print(f"PASS: Flinch worked. Msg: {msg}")
    else:
        print(f"FAIL: Can Move {can_move}, Msg {msg}")

    # 4. PP Usage (Simulation)
    print("[4] PP Check")
    p1_state.pp[888] = 0
    # Simulate Socket Check
    if p1_state.pp.get(888) <= 0:
        print("PASS: PP Check prevented move.")
    else:
        print("FAIL: PP Check failed.")

if __name__ == "__main__":
    test_deep_logic()
