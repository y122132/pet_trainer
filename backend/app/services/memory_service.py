from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc
from app.db.models.memory import CharacterMemory, MemorySummary, MemoryType
from datetime import datetime
from langchain_openai import ChatOpenAI
from langchain_core.messages import SystemMessage, HumanMessage
import os
import json

class MemoryService:
    @staticmethod
    async def add_memory(
        db: AsyncSession, 
        character_id: int, 
        memory_type: MemoryType | str, 
        content: str, 
        meta_info: dict = None
    ):
        """
        기억을 저장하고, 필요 시 요약(Summary) 프로세스를 트리거합니다.
        """
        # 1. 기억 저장
        new_memory = CharacterMemory(
            character_id=character_id,
            memory_type=memory_type,
            content=content,
            meta_info=meta_info or {},
            created_at=datetime.utcnow()
        )
        db.add(new_memory)
        await db.commit()
        await db.refresh(new_memory)
        
        # 2. 요약 트리거 체크 (단순 갯수 체크: 10개 단위)
        # 아직 요약되지 않은(연결된 Summary가 없는) 기억의 개수를 세는 로직은 복잡할 수 있으므로,
        # 여기서는 단순히 총 기억 개수 혹은 가장 최근 Summary 이후의 기억 개수를 셉니다.
        
        # 가장 최근 Summary 조회
        stmt = (
            select(MemorySummary)
            .where(MemorySummary.character_id == character_id)
            .order_by(desc(MemorySummary.end_memory_id))
            .limit(1)
        )
        result = await db.execute(stmt)
        last_summary = result.scalar_one_or_none()
        
        last_summary_end_id = last_summary.end_memory_id if last_summary else 0
        
        # 요약되지 않은 기억 조회
        stmt_unsummarized = (
            select(CharacterMemory)
            .where(CharacterMemory.character_id == character_id)
            .where(CharacterMemory.id > last_summary_end_id)
            .order_by(CharacterMemory.id.asc())
        )
        result_memories = await db.execute(stmt_unsummarized)
        unsummarized_memories = result_memories.scalars().all()
        
        # 10개 이상이면 요약 실행
        if len(unsummarized_memories) >= 10:
            await MemoryService._generate_summary(db, character_id, unsummarized_memories)
            
    @staticmethod
    async def _generate_summary(db: AsyncSession, character_id: int, memories: list[CharacterMemory]):
        """
        [Internal] LLM을 사용하여 기억 리스트를 요약하고 저장합니다.
        """
        print(f"[Memory] Generating Summary for {len(memories)} memories...")
        
        # 텍스트 변환
        memory_text = "\n".join([f"- [{m.memory_type}] {m.content}" for m in memories])
        
        # LLM 호출
        llm = ChatOpenAI(model="gpt-4o-mini", temperature=0.5, api_key=os.getenv("OPENAI_API_KEY"))
        
        prompt = f"""
        당신은 AI 캐릭터의 '기억 관리자'입니다. 
        아래 나열된 캐릭터의 최근 기억들을 하나의 문단으로 자연스럽게 요약해주세요.
        중요한 사건(배틀, 성공한 훈련 등)은 포함하고, 단순 반복적인 내용은 간략화하세요.
        
        [기억 목록]
        {memory_text}
        
        [요약 가이드]
        - 시점: 3인칭 관찰자 시점 (예: "주인님과 산책을 했다.") 혹은 1인칭
        - 분량: 2~3문장
        - 언어: 한국어
        """
        
        try:
            response = await llm.ainvoke([SystemMessage(content="You are a memory sunmmarizer."), HumanMessage(content=prompt)])
            summary_content = response.content
            
            # DB 저장
            new_summary = MemorySummary(
                character_id=character_id,
                start_memory_id=memories[0].id,
                end_memory_id=memories[-1].id,
                summary_text=summary_content,
                created_at=datetime.utcnow()
            )
            db.add(new_summary)
            await db.commit()
            print(f"[Memory] Summary Created: {summary_content[:30]}...")
            
        except Exception as e:
            print(f"[Memory] Summary Generation Failed: {e}")

    @staticmethod
    async def get_recent_context(db: AsyncSession, character_id: int) -> str:
        """
        LLM Context 주입용: 최근 요약 1개 + 최근 요약되지 않은 기억들
        """
        context_str = ""
        
        # 1. 최근 요약 가져오기
        stmt_sum = (
            select(MemorySummary)
            .where(MemorySummary.character_id == character_id)
            .order_by(desc(MemorySummary.id))
            .limit(1)
        )
        res_sum = await db.execute(stmt_sum)
        latest_summary = res_sum.scalar_one_or_none()
        
        last_mem_id = 0
        if latest_summary:
            context_str += f"[과거 기억 요약]: {latest_summary.summary_text}\n"
            last_mem_id = latest_summary.end_memory_id
            
        # 2. 그 이후의 최근 기억들 (최대 10개)
        stmt_mem = (
            select(CharacterMemory)
            .where(CharacterMemory.character_id == character_id)
            .where(CharacterMemory.id > last_mem_id)
            .order_by(CharacterMemory.id.asc())
            .limit(10) # Safety limit
        )
        res_mem = await db.execute(stmt_mem)
        recents = res_mem.scalars().all()
        
        if recents:
            context_str += "[최근 기억]:\n"
            for m in recents:
                context_str += f"- {m.content}\n"
                
        if not context_str:
            context_str = "(아직 특별한 기억이 없습니다.)"
            
        return context_str
