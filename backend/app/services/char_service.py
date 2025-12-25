from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.db.models.character import Character, Stat, ActionLog
from datetime import datetime

async def update_stats_from_yolo_result(db: AsyncSession, char_id: int, yolo_result: dict):
    """
    YOLO 분석 결과(성공 시)를 바탕으로 캐릭터의 스탯을 업데이트하고 행동 로그를 저장합니다.
    """
    if not yolo_result.get("success"):
        return None

    # 1. 캐릭터 스탯 조회
    result = await db.execute(select(Stat).where(Stat.character_id == char_id))
    stat = result.scalar_one_or_none()
    
    if not stat:
        # 스탯이 없으면 중단 (실제 앱에서는 에러 처리 필요)
        return None

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
    else:
        # 보상 정보가 없는 경우 기본값 (안전장치)
        stat.strength += 1
        updated_stat_val = stat.strength
        
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
        "milestone_reached": milestone_reached
    }

async def get_character_with_stats(db: AsyncSession, char_id: int):
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
    from app.db.models.user import User

    # 1. 사용자 확인 또는 생성 (간소화된 MVP 로직)
    stmt = select(User).where(User.id == user_id)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()
    
    if not user:
        user = User(id=user_id, email=f"user{user_id}@example.com", hashed_password="dummy")
        db.add(user)
        await db.commit()
    
    # 2. 기존 캐릭터 확인 (중복 생성 방지)
    stmt = select(Character).where(Character.user_id == user_id)
    result = await db.execute(stmt)
    existing_char = result.scalar_one_or_none()
    
    if existing_char:
        return existing_char

    # 3. 캐릭터 생성
    new_char = Character(user_id=user_id, name=name, status="normal", pet_type=pet_type)
    db.add(new_char)
    await db.flush() # ID 생성을 위해 flush (commit 전 ID 확보)
    
    # 4. 초기 스탯 설정 (기본값)
    # 4. 초기 스탯 설정 (종족값 반영)
    from app.game.game_assets import PET_BASE_STATS
    
    # Default to Dog (Balanced) if type not found
    base_stats = PET_BASE_STATS.get(pet_type, PET_BASE_STATS["dog"])
    
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
    return await get_character_with_stats(db, new_char.id)

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

async def process_battle_result(db: AsyncSession, winner_id: int, loser_id: int):
    """
    전투 종료 후 승자에게 경험치를 지급하고 레벨업 및 스킬 습득을 처리합니다.
    """
    from app.game.game_assets import PET_LEARNSET
    
    # 1. 승자 캐릭터 조회
    char_obj = await get_character_with_stats(db, winner_id) # 이미 서비스 내에 있는 함수 활용 (user_id가 아니라 char_id를 받아야 하는데...)
    
    # get_character_with_stats는 char_id를 받으므로, user_id로 먼저 조회해야 함.
    # 하지만 편의상 이 함수 내에서 user_id로 조회하도록 로직 작성.
    stmt = select(Character).where(Character.user_id == winner_id)
    res = await db.execute(stmt)
    winner_char = res.scalar_one_or_none()
    
    if not winner_char:
        return None
        
    # Lazy loading 방지를 위해 Stat 재조회 혹은 위에서 옵션 로드 했다고 가정
    # 여기서는 안전하게 Stat 직접 조회
    stmt_stat = select(Stat).where(Stat.character_id == winner_char.id)
    res_stat = await db.execute(stmt_stat)
    stat = res_stat.scalar_one_or_none()
    
    if not stat:
        return None

    # 2. 경험치 지급
    exp_gain = 50 # 기본 50 (레벨 차이 등 공식 적용 가능)
    stat.exp += exp_gain
    
    # 3. 레벨업 체크
    # 레벨업 공식: 필요 경험치 = Level * 100 (단순화)
    # 1->2: 100, 2->3: 200 ...
    level_up_occurred = False
    new_skills = []
    
    while stat.exp >= stat.level * 100:
        stat.exp -= stat.level * 100
        stat.level += 1
        level_up_occurred = True
        
        # 스탯 자동 증가
        stat.strength += 2
        stat.defense += 2
        stat.agility += 2
        stat.health += 10
        stat.unused_points += 1
        
        # 4. 신규 기술 습득 체크
        pet_type = winner_char.pet_type.lower()
        learnset = PET_LEARNSET.get(pet_type, {})
        skills_at_level = learnset.get(stat.level, [])
        
        current_skills = winner_char.learned_skills or []
        
        for skill_id in skills_at_level:
            if skill_id not in current_skills:
                current_skills.append(skill_id)
                new_skills.append(skill_id)
        
        # JSONB 업데이트를 위해 새로운 리스트 할당 (SQLAlchemy 감지용)
        winner_char.learned_skills = list(current_skills)

    await db.commit()
    
    return {
        "exp_gained": exp_gain,
        "new_level": stat.level,
        "level_up": level_up_occurred,
        "new_skills": new_skills
    }