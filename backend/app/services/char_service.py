from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.db.models.character import Character, Stat, ActionLog
from datetime import datetime
from app.game.game_assets import PET_LEARNSET
from sqlalchemy.orm import Session, selectinload

async def update_stats_from_yolo_result(db: AsyncSession, char_id: int, yolo_result: dict):
    """
    YOLO 분석 결과(성공 시)를 바탕으로 캐릭터의 스탯을 업데이트하고 행동 로그를 저장합니다.
    """
    if not yolo_result.get("success"):
        return None

    # 1. 캐릭터와 스탯 조회 (Eager Loading)
    # [Optimization] N+1 Problem Solved: Fetch Character AND Stat in one query
    stmt = select(Character).options(selectinload(Character.stat)).where(Character.id == char_id)
    result = await db.execute(stmt)
    character = result.scalar_one_or_none()
    
    if not character or not character.stat:
        return None
        
    stat = character.stat

    # 2. 행동 로그 저장 (히스토리 추적용)
    action_type = yolo_result.get("action_type", "unknown")
    
    action_log = ActionLog(
        character_id=char_id,
        action_type=action_type,
        yolo_result_json=yolo_result
    )
    db.add(action_log)
    
    # 3. 스탯 업데이트 (base_reward 정보 활용)
    base_reward = yolo_result.get("base_reward", {})
    updated_stat_val = 0
    
    if base_reward:
        stype = base_reward.get("stat_type")
        val = base_reward.get("value", 0)
        
        if stype == "strength":     # 근력
            stat.strength += val
            updated_stat_val = stat.strength
        elif stype == "intelligence": # 지능
            stat.intelligence += val
            updated_stat_val = stat.intelligence
        elif stype == "agility":    # 민첩
            stat.agility += val
            updated_stat_val = stat.agility
        elif stype == "defense":    # 방어
            stat.defense += val
            updated_stat_val = stat.defense
        elif stype == "luck":       # 운
            stat.luck += val
            updated_stat_val = stat.luck
        elif stype == "happiness":  # 행복도
            stat.happiness += val
            updated_stat_val = stat.happiness
        elif stype == "health":     # 체력
            stat.health += val
            updated_stat_val = stat.health
            
        # [New] Bonus Points for User Distribution
        bonus = yolo_result.get("bonus_points", 0)
        if bonus > 0:
            stat.unused_points += bonus
    else:
        # 보상 정보가 없는 경우 기본값 (안전장치)
        stat.strength += 1
        updated_stat_val = stat.strength

    # [Fix] Grant EXP for Training Success
    # Training grants 30 EXP by default
    exp_gain = 30
    
    # [Optimization] Removed redundant character fetch
    # We already have 'character' from the initial eager load
    
    level_up_info = {}
    if character:
        # Note: _give_exp_and_levelup uses character.stat directly now
        # But we might need to explicit flush if we modified stat above
        await db.flush()
        
        level_up_info = await _give_exp_and_levelup(db, character, exp_gain) 
        
        # No need to refresh stat manually if object is same session attached
    
        
    # 4. 마일스톤(목표 달성) 체크
    # 예: 스탯이 10단위(10, 20, 30...)에 도달했을 때 이펙트 발생
    milestone_reached = False
    if updated_stat_val > 0 and updated_stat_val % 10 == 0:
        milestone_reached = True

    # 5. DB 커밋 및 갱신
    await db.commit()
    await db.refresh(stat)
    
    # 6. 일일 수행 횟수 계산 (오늘 날짜 기준)
    today_start = datetime.utcnow().date()
    
    stmt = select(func.count(ActionLog.id)).where(
        ActionLog.character_id == char_id,
        ActionLog.action_type == action_type,
        ActionLog.created_at >= today_start
    )
    count_res = await db.execute(stmt)
    daily_count = count_res.scalar_one()

    return {
        "stat": stat,
        "daily_count": daily_count,
        "milestone_reached": milestone_reached,
        "level_up_info": level_up_info # Pass this up
    }

async def get_character(db: AsyncSession, char_id: int):
    """
    캐릭터 정보와 스탯을 함께 조회합니다.
    """
    # Eager Loading(selectinload)을 사용하여 연관된 스탯 정보까지 한번에 가져옴 (N+1 문제 방지)
    from sqlalchemy.orm import selectinload
    stmt = select(Character).options(selectinload(Character.stat)).where(Character.id == char_id)
    result = await db.execute(stmt)
    character = result.scalar_one_or_none()
    return character

async def create_character(db: AsyncSession, user_id: int, name: str, pet_type: str = "dog"):
    """
    새로운 사용자와 캐릭터를 생성합니다. (초기 자산 및 스탯 지급)
    """
    print(f"--- [DEBUG] create_character called: user_id={user_id}, name={name}, pet_type={pet_type} ---")
    from app.db.models.user import User

    # 1. 사용자 확인 또는 생성 (간소화된 MVP 로직)
    stmt = select(User).where(User.id == user_id)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()
    
    if not user:
        # 회원이 존재하지 않으면 에러 발생 (인증된 유저만 캐릭터 생성 가능)
        raise ValueError("User not found")
    
    # 2. 기존 캐릭터 확인 (중복 생성 방지)
    stmt = select(Character).where(Character.user_id == user_id)
    result = await db.execute(stmt)
    existing_char = result.scalar_one_or_none()
    
    if existing_char:
        # [Dev Only] 유저 편의를 위해 만약 이미 캐릭터가 있다면 정보를 업데이트함
        # (실제 서비스에서는 '이미 캐릭터가 있습니다' 에러를 내거나 '초기화' 메뉴를 따로 둠)
        print(f"[CharService] Updating existing character {existing_char.id} for user {user_id}")
        existing_char.pet_type = pet_type
        existing_char.name = name
        
        pet_type_lower = pet_type.lower()
        from app.game.game_assets import PET_LEARNSET, PET_BASE_STATS
        
        initial_skills = [5]
        if pet_type_lower in PET_LEARNSET:
            initial_skills = PET_LEARNSET[pet_type_lower].get(5, [5])
            
        existing_char.learned_skills = initial_skills
        existing_char.equipped_skills = initial_skills
        
        # 스탯 리셋
        from sqlalchemy.orm import selectinload
        stmt_stat = select(Stat).where(Stat.character_id == existing_char.id)
        res_stat = await db.execute(stmt_stat)
        stat = res_stat.scalar_one_or_none()
        
        base_stats = PET_BASE_STATS.get(pet_type_lower, PET_BASE_STATS["dog"])
        if stat:
            stat.strength = base_stats.get("strength", 10)
            stat.intelligence = base_stats.get("intelligence", 10)
            stat.defense = base_stats.get("defense", 10)
            stat.agility = base_stats.get("agility", 10)
            stat.luck = base_stats.get("luck", 10)
            stat.level = 5 # Reset to 5 anyway
            stat.exp = 0
            stat.health = 100
        
        # [New] Re-unlock skills for the current level (if skipping levels or just ensuring consistency)
        await check_and_unlock_skills(db, existing_char, stat.level if stat else 5)
        
        await db.commit()
        return await get_character(db, existing_char.id)

    # 3. 캐릭터 생성
    from app.game.game_assets import PET_LEARNSET
    
    # Get initial skills (Lv 5 skills)
    initial_skills = [5] # Default
    pet_type_lower = pet_type.lower()
    if pet_type_lower in PET_LEARNSET:
        initial_skills = PET_LEARNSET[pet_type_lower].get(5, [5])
    
    print(f"--- [DEBUG] Determined initial_skills for {pet_type_lower}: {initial_skills} ---")

    new_char = Character(
        user_id=user_id, 
        name=name, 
        status="normal", 
        pet_type=pet_type,
        learned_skills=initial_skills,
        equipped_skills=initial_skills
    )
    db.add(new_char)
    await db.flush() # ID 생성을 위해 flush (commit 전 ID 확보)
    
    # 4. 초기 스탯 설정 (종족값 반영)
    from app.game.game_assets import PET_BASE_STATS
    
    # Default to Dog (Balanced) if type not found
    base_stats = PET_BASE_STATS.get(pet_type_lower, PET_BASE_STATS["dog"])
    
    new_stat = Stat(
        character_id=new_char.id, 
        strength=base_stats.get("strength", 10), 
        intelligence=base_stats.get("intelligence", 10), 
        defense=base_stats.get("defense", 10),
        agility=base_stats.get("agility", 10), 
        luck=base_stats.get("luck", 10),
        happiness=70, 
        health=100
    )
    db.add(new_stat)
    
    await db.commit()
    await db.refresh(new_char)
    
    # 생성된 캐릭터 반환 (스탯 포함)
    return await get_character(db, new_char.id)

async def update_character_stats(db: AsyncSession, char_id: int, stats_update: dict):
    """
    API 요청으로 캐릭터 스탯을 직접 수정합니다. (클라이언트 동기화 또는 포인트 분배용)
    """
    stmt = select(Stat).where(Stat.character_id == char_id)
    result = await db.execute(stmt)
    stat = result.scalar_one_or_none()
    
    if not stat:
        return None
        
    # 전달된 필드만 업데이트 (Partial Update)
    if "strength" in stats_update: stat.strength = stats_update["strength"]
    if "intelligence" in stats_update: stat.intelligence = stats_update["intelligence"]
    if "agility" in stats_update: stat.agility = stats_update["agility"]
    if "defense" in stats_update: stat.defense = stats_update["defense"]
    if "luck" in stats_update: stat.luck = stats_update["luck"]
    if "happiness" in stats_update: stat.happiness = stats_update["happiness"]
    if "health" in stats_update: stat.health = stats_update["health"]
    if "unused_points" in stats_update: stat.unused_points = stats_update["unused_points"]
    if "exp" in stats_update: stat.exp = stats_update["exp"]
    if "level" in stats_update: stat.level = stats_update["level"]
    
    await db.commit()
    await db.refresh(stat)
    return stat

async def _give_exp_and_levelup(db: AsyncSession, character: Character, exp_gain: int) -> dict:
    from app.game.game_assets import PET_LEARNSET, PET_BASE_STATS, MOVE_DATA
    
    # [Optimization] Use eager loaded stat if available
    stat = character.stat
    
    if not stat:
        # Fallback (should not happen if eager loading is used properly)
        stmt_stat = select(Stat).where(Stat.character_id == character.id)
        res_stat = await db.execute(stmt_stat)
        stat = res_stat.scalar_one_or_none()
        
    if not stat:
        return {}

    print(f"[DEBUG] _give_exp_and_levelup called. Init Level: {stat.level}, Exp Gain: {exp_gain}")
    
    stat.exp += exp_gain
    
    level_up_occurred = False
    newly_acquired_skills_info = [] # Init here just in case

    # 레벨업 체크
    while stat.level < 100 and stat.exp >= stat.level * 100:
        stat.exp -= stat.level * 100
        stat.level += 1
        stat.unused_points += 5
        level_up_occurred = True
        print(f"[DEBUG] Level Up! New Level: {stat.level}")
        
        # 스탯 성장
        pet_type = character.pet_type.lower()
        base_stats = PET_BASE_STATS.get(pet_type, PET_BASE_STATS["dog"])
        
        stat.strength += max(1, int(base_stats.get("strength", 10) * 0.2))
        stat.defense += max(1, int(base_stats.get("defense", 10) * 0.2))
        stat.agility += max(1, int(base_stats.get("agility", 10) * 0.2))
        stat.intelligence += max(1, int(base_stats.get("intelligence", 10) * 0.2))
        stat.health += 10 # HP Boost
        stat.unused_points += 1
        
    # [New] Enforce Max Level Cap
    if stat.level >= 100:
        stat.level = 100
        stat.exp = 0 # Optional: clear exp at max level
        
    # [Fix] Retroactive Skill Check (Ensure nothing skipped)
    # Check all levels up to current level
    pet_type = character.pet_type.lower()
    learnset = PET_LEARNSET.get(pet_type, {})
    
    # Reload current skills to be sure
    current_skills = set(character.learned_skills or [])
    initial_skill_count = len(current_skills)
    
    newly_acquired_skills_info = [] # List of {level, name, id}
    
    # Iterate through all levels in learnset
    for lv, skill_ids in learnset.items():
        if stat.level >= lv: # Check if level requirement met
            for skill_id in skill_ids:
                if skill_id not in current_skills:
                    current_skills.add(skill_id)
                    skill_name = MOVE_DATA.get(skill_id, {}).get("name", "Unknown Skill")
                    newly_acquired_skills_info.append({
                        "id": skill_id,
                        "name": skill_name, 
                        "level": lv
                    })
                    print(f"[DEBUG] Skill Acquired: {skill_name} (ID: {skill_id}) at Lv {stat.level} (Unlock Lv {lv})")
                    
    if len(current_skills) > initial_skill_count:
        character.learned_skills = list(current_skills)
        level_up_occurred = True 

    await db.commit()
    
    print(f"[DEBUG] Final Result - New Skills: {newly_acquired_skills_info}")

    
    return {
        "exp_gained": exp_gain,
        "new_level": stat.level,
        "new_exp": stat.exp,
        "level_up": level_up_occurred,
        "new_skills": list(current_skills), # Return full list
        "acquired_skills_details": newly_acquired_skills_info, # New field for notification
        "unused_points": stat.unused_points
    }

async def process_battle_result(db: AsyncSession, winner_id: int, loser_id: int):
    # 1. 승자 캐릭터 조회
    stmt = (
        select(Character)
        .options(selectinload(Character.stat)) 
        .where(Character.user_id == winner_id)
    )
    res = await db.execute(stmt)
    winner_char = res.scalar_one_or_none()
    
    if not winner_char:
        return None
        
    if loser_id == 0:
        print("[CharService] Battle vs Bot finished. Winner: Human")
        
    return await _give_exp_and_levelup(db, winner_char, exp_gain=50)

async def process_battle_draw(db: AsyncSession, user_id1: int, user_id2: int):
    rewards = {}
    
    stmt = (
        select(Character)
        .options(selectinload(Character.stat))
        .where(Character.user_id.in_([user_id1, user_id2]))
    )
    result = await db.execute(stmt)
    chars = result.scalars().all()
    
    for char in chars:
        rewards[char.user_id] = await _give_exp_and_levelup(db, char, exp_gain=25)
        
    return rewards

async def update_character_image_urls(db: AsyncSession, char_id: int, image_urls_update: dict):
    """
    API 요청으로 캐릭터의 이미지 URL들을 직접 수정합니다.
    """
    stmt = select(Character).where(Character.id == char_id)
    result = await db.execute(stmt)
    character = result.scalar_one_or_none()
    
    if not character:
        return None
        
    # 전달된 필드만 업데이트 (Partial Update)
    if "profile_url" in image_urls_update: character.profile_url = image_urls_update["profile_url"]

    if "front_url" in image_urls_update: character.front_url = image_urls_update["front_url"]
    if "back_url" in image_urls_update: character.back_url = image_urls_update["back_url"]
    if "side_url" in image_urls_update: character.side_url = image_urls_update["side_url"]
    if "face_url" in image_urls_update: character.face_url = image_urls_update["face_url"]

    # [New] Additional Directions
    if "front_left_url" in image_urls_update: character.front_left_url = image_urls_update["front_left_url"]
    if "front_right_url" in image_urls_update: character.front_right_url = image_urls_update["front_right_url"]
    if "back_left_url" in image_urls_update: character.back_left_url = image_urls_update["back_left_url"]
    if "back_right_url" in image_urls_update: character.back_right_url = image_urls_update["back_right_url"]
    
    await db.commit()
    await db.refresh(character)
    return character

async def delete_character(db: AsyncSession, char_id: int) -> bool:
    """
    캐릭터를 DB에서 완전히 삭제합니다. (생성 실패 시 롤백용)
    """
    stmt = select(Character).where(Character.id == char_id)
    result = await db.execute(stmt)
    character = result.scalar_one_or_none()
    
    if character:
        await db.delete(character)
        await db.commit()
        return True
    return False

async def check_and_unlock_skills(db: Session, character: Character, current_level: int):
    pet_type = character.pet_type.lower()
    learnset = PET_LEARNSET.get(pet_type, {})
    
    should_be_learned = []
    for lv, skill_ids in learnset.items():
        if current_level >= lv:
            should_be_learned.extend(skill_ids)
    
    updated_learned_skills = list(set((character.learned_skills or []) + should_be_learned))
    
    if len(updated_learned_skills) > len(character.learned_skills or []):
        character.learned_skills = updated_learned_skills
        db.add(character)
        await db.commit()
        print(f"--- [해금 성공] 새 스킬이 추가되었습니다: {updated_learned_skills} ---")