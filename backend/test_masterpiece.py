from app.game.game_assets import PET_BASE_STATS, MOVE_DATA
from app.game.battle_manager import BattleManager, BattleState

# Mock Data for Field Move
MOVE_DATA[999] = {
    "name": "Sunny Day Mock",
    "type": "fire",
    "category": "status",
    "effect": {"type": "field_change", "field": "weather", "value": "sun", "target": "room"},
    "effect_chance": 100
}

def test_masterpiece():
    print("=== Testing Masterpiece Logic ===")
    
    # 1. Growth Logic Check
    print("[1] Dynamic Growth Check")
    # Formula: max(1, int(Base * 0.2))
    # Bear Str 15 -> 3
    # Cat Str 9 -> 1
    
    bear_str_base = PET_BASE_STATS["bear"]["strength"]
    cat_str_base = PET_BASE_STATS["cat"]["strength"]
    
    bear_growth = max(1, int(bear_str_base * 0.2))
    cat_growth = max(1, int(cat_str_base * 0.2))
    
    print(f"Bear Base Str: {bear_str_base} -> Growth: {bear_growth}")
    print(f"Cat Base Str: {cat_str_base} -> Growth: {cat_growth}")
    
    if bear_growth > cat_growth:
        print("PASS: Bear grows stronger than Cat.")
    else:
        print("FAIL: Growth logic flawed.")

    # 2. Field Effect Logic Check
    print("[2] Field Move Effect Check")
    # We test BattleManager.apply_move_effects returns correct log
    # We can't test Socket directly easily without async mock, but Manager return is key.
    
    attacker_state = BattleState()
    defender_state = BattleState()
    p_stat = type("Stat", (), {"strength": 10})()
    
    logs = BattleManager.apply_move_effects(999, attacker_state, defender_state, p_stat, "P1", "P2")
    print(f"DEBUG: Logs generated: {logs}")
    
    field_log = next((l for l in logs if l["type"] == "field_update"), None)
    
    if field_log:
        print(f"PASS: Field Update Log Generated: {field_log['message']}")
        if field_log["field"] == "weather" and field_log["value"] == "sun":
             print("PASS: Correct Field Values.")
        else:
             print("FAIL: Incorrect Values.")
    else:
        print("FAIL: No Field Update Log.")

if __name__ == "__main__":
    test_masterpiece()
