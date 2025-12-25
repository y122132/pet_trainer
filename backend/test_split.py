from app.game.battle_manager import BattleManager, BattleState
from app.game.game_assets import MOVE_DATA

# Mock Data
MOVE_DATA[901] = {
    "name": "Physical Hit",
    "category": "physical",
    "power": 50,
    "type": "normal"
}
MOVE_DATA[902] = {
    "name": "Special Beam",
    "category": "special",
    "power": 50,
    "type": "normal"
}

def test_split():
    print("=== Testing Physical/Special Split ===")
    
    # Setup: Muscle Cat (High Str, Low Int) vs Smart Dog (High Int, Low Def)
    p1_stat = type("Stat", (), {"strength": 100, "intelligence": 10, "defense": 10, "luck": 10})() # Muscle
    p2_stat = type("Stat", (), {"strength": 10, "intelligence": 100, "defense": 10, "luck": 10})() # Smart
    
    p1_state = BattleState()
    p2_state = BattleState()
    
    # 1. Muscle Cat uses Physical Move on Smart Dog (Low Def 10). Should hurt A LOT.
    dmg_phy, _, _ = BattleManager.calculate_damage(p1_stat, p1_state, p2_stat, p2_state, 901)
    
    # 2. Muscle Cat uses Special Move on Smart Dog (High Int 100). Should hurt LITTLE.
    dmg_spe, _, _ = BattleManager.calculate_damage(p1_stat, p1_state, p2_stat, p2_state, 902)
    
    print(f"Physical Damage (Str 100 vs Def 10): {dmg_phy}")
    print(f"Special Damage (Int 10 vs Int 100): {dmg_spe}")
    
    if dmg_phy > dmg_spe * 3:
        print("PASS: Physical damage vastly superior due to stat split.")
    else:
        print("FAIL: Damage split logic not working properly.")

if __name__ == "__main__":
    test_split()
