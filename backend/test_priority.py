from app.game.battle_manager import BattleManager, BattleState
from app.game.game_assets import MOVE_DATA

# Mock Data
MOVE_DATA[777] = {
    "name": "Slow Punch",
    "priority": 0,
    "power": 50
}
MOVE_DATA[778] = {
    "name": "Quick Attack",
    "priority": 1,
    "power": 40
}

def test_priority():
    print("=== Testing Priority Logic ===")
    
    # 1. Setup: P1 is FAST, P2 is SLOW
    p1_stat = type("Stat", (), {"agility": 100, "strength": 10, "defense": 10, "luck": 10})()
    p2_stat = type("Stat", (), {"agility": 10, "strength": 10, "defense": 10, "luck": 10})()
    
    p1_state = BattleState()
    p2_state = BattleState()
    
    # Case A: Normal Speed Check (Fast P1 vs Slow P2)
    # Both use Slow Punch (Priority 0)
    order = BattleManager.determine_turn_order(
        p1_stat, p1_state, 777,
        p2_stat, p2_state, 777
    )
    print(f"Case A (Speed only): Winner is P{order}")
    if order == 1:
        print("PASS: Fast pet went first.")
    else:
        print("FAIL: Slow pet went first.")
        
    # Case B: Priority Check (Fast P1 uses Slow Move, Slow P2 uses Quick Attack)
    order = BattleManager.determine_turn_order(
        p1_stat, p1_state, 777,
        p2_stat, p2_state, 778
    )
    print(f"Case B (Priority): Winner is P{order}")
    if order == 2:
        print("PASS: Slow pet with Priority used move first.")
    else:
        print("FAIL: Priority ignored.")

if __name__ == "__main__":
    test_priority()
