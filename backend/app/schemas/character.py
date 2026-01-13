from pydantic import BaseModel
from typing import List

class EquipSkillsRequest(BaseModel):
    skill_ids: List[int] # 유저가 선택한 4개의 스킬 ID