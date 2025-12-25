from app.game.game_assets import MOVE_DATA, PET_BASE_STATS, PET_LEARNSET

def test_content_integrity():
    print("=== Content Integrity Check ===")
    
    # 1. Base Stats Check
    print(f"Species Defined: {list(PET_BASE_STATS.keys())}")
    for species, stats in PET_BASE_STATS.items():
        if "strength" not in stats or "intelligence" not in stats:
            print(f"FAIL: {species} missing stats")
        else:
            print(f"PASS: {species} stats valid")

    # 2. Move Data Check
    print(f"Total Moves: {len(MOVE_DATA)}")
    move_ids_in_data = set(MOVE_DATA.keys())
    
    # 3. Learnset Link Check
    all_valid = True
    for species, learnset in PET_LEARNSET.items():
        for level, moves in learnset.items():
            for mid in moves:
                if mid not in move_ids_in_data:
                    print(f"FAIL: {species} learns Move ID {mid} which is NOT in MOVE_DATA")
                    all_valid = False
                    
    if all_valid:
        print("PASS: All Learnset moves exist in MOVE_DATA")
    
    # 4. Category Check
    print("Checking Categories...")
    for mid, mdata in MOVE_DATA.items():
        cat = mdata.get("category")
        if cat not in ["physical", "special", "status"]:
            print(f"WARNING: Move {mid} ({mdata['name']}) has invalid category: {cat}")
            
    print("=== Done ===")

if __name__ == "__main__":
    test_content_integrity()
