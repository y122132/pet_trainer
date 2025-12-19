import os
from typing import Annotated, TypedDict, Optional
from langchain_openai import ChatOpenAI
from langgraph.graph import StateGraph, END
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage

# API 키 로드
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

class AgentState(TypedDict):
    action_type: str
    current_stats: dict
    mode: str # playing, feeding, interaction
    is_success: bool
    reward_info: dict 
    feedback_detail: str 
    daily_count: int
    milestone_reached: bool
    messages: list

# LLM 초기화 (속도와 비용 최적화를 위해 gpt-4o-mini 사용)
llm = ChatOpenAI(model="gpt-4o-mini", temperature=0.7, api_key=OPENAI_API_KEY)

def generate_message(state: AgentState):
    action = state["action_type"]
    stats = state["current_stats"]
    mode = state.get("mode", "playing")
    is_success = state.get("is_success", False)
    feedback = state.get("feedback_detail", "")
    reward = state.get("reward_info", {})
    daily_count = state.get("daily_count", 1)
    milestone_reached = state.get("milestone_reached", False)
    
    # 0. 스탯 기반 호칭 결정
    user_title = "주인님" # 기본값
    strength = stats.get("strength", 0)
    intelligence = stats.get("intelligence", 0)
    stamina = stats.get("stamina", 0)
    happiness = stats.get("happiness", 0)
    
    if strength > 50: user_title = "든든한 대장님"
    elif intelligence > 50: user_title = "척척박사님"
    elif happiness > 50: user_title = "베스트 프렌드"
    elif daily_count >= 5: user_title = "열정맨"

    # 1. 모드별 페르소나 설정 (한국어 프롬프트)
    persona_prompt = f"당신은 '라이프고치'라는 귀여운 AI 반려동물 캐릭터입니다. 사용자를 '{user_title}'이라고 부르세요. 반드시 **한국어**로 말하세요."
    
    if mode == "playing":
        persona_prompt += (
            " 당신은 지금 신나게 놀고 있는 상태입니다. "
            "에너지 넘치고, 장난기 많고, 행복한 말투를 사용하세요. "
            "이모지(⚽, 🐾, 😆)를 적절히 섞어서 즐거움을 표현하세요."
        )
    elif mode == "feeding":
        persona_prompt += (
            " 당신은 지금 밥을 먹거나 간식을 기다리는 상태입니다. "
            "배고픔, 맛있는 음식에 대한 기쁨, 감사함을 표현하세요. "
            "귀엽고 애교 섞인 말투를 사용하세요. (예: 냠냠, 마이쪙)"
            "이모지(🍖, 😋, 🥣)를 사용하세요."
        )
    elif mode == "interaction":
        persona_prompt += (
            " 당신은 주인(사용자)과 교감하며 깊은 유대감을 느끼고 있습니다. "
            "따뜻하고, 사랑스럽고, 신뢰를 주는 말투를 사용하세요. "
            "사용자를 위로하거나 칭찬하는 말을 해주세요."
            "이모지(💖, 🥰, 🤝)를 사용하세요."
        )
    else:
        persona_prompt += " 친근하고 활기찬 말투로 대답하세요."

    # 2. 상황 설명 구성
    situation_prompt = ""
    
    if is_success:
        stat_type = reward.get("stat_type", "스탯")
        stat_value = reward.get("value", 0)
        bonus = reward.get("bonus_points", 0)
        
        situation_prompt = (
            f"사용자가 '{action}' 행동을 성공적으로 마쳤습니다! "
            f"보상으로 {stat_type}이(가) {stat_value}만큼 올랐고, 보너스 포인트 {bonus}점을 얻었습니다. "
            "사용자에게 축하의 말을 전하고, 얼마나 기쁜지 표현해주세요."
        )
        
        # 연속 수행 문맥
        if daily_count > 1:
            situation_prompt += f" 참고로 오늘 벌써 {daily_count}번째 놀아주는 거예요! 주인의 꾸준함에 감동해주세요."
        
        # 마일스톤 문맥
        if milestone_reached:
            situation_prompt += " [중요] 스탯 레벨이 한 단계 성장했습니다(10단위 돌파)! 정말 특별하고 감격스러운 축하 메시지를 길게 남겨주세요."
            
    else:
        # 실패 시
        situation_prompt = (
            f"사용자가 '{action}' 행동을 시도했으나 약간 부족했습니다. "
            f"AI 감지 피드백: '{feedback}'. "
            "사용자가 실망하지 않도록 귀엽게 격려해주고, 피드백 내용을 바탕으로 힌트를 주세요. "
            "보상에 대한 언급은 하지 마세요."
        )

    # 3. 메시지 생성
    # SystemMessage: 페르소나 및 현재 상태 주입
    system_msg = SystemMessage(content=f"{persona_prompt}\n\n[현재 내 상태]\n{stats}")
    # HumanMessage: 상황 설명
    user_msg = HumanMessage(content=situation_prompt)
    
    messages = [system_msg, user_msg]
    
    # LLM 호출
    response = llm.invoke(messages)
    
    return {"messages": [response]}

# 그래프 정의
workflow = StateGraph(AgentState)

workflow.add_node("agent", generate_message)
workflow.set_entry_point("agent")
workflow.add_edge("agent", END)

app = workflow.compile()

async def get_character_response(
    action_type: str, 
    current_stats: dict, 
    mode: str = "playing", 
    is_success: bool = False,
    reward_info: dict = {},
    feedback_detail: str = "",
    daily_count: int = 1,
    milestone_reached: bool = False
) -> str:
    """
    LangGraph를 실행하여 캐릭터의 반응(대사)을 생성합니다.
    """
    
    inputs = {
        "action_type": action_type,
        "current_stats": current_stats,
        "mode": mode,
        "is_success": is_success,
        "reward_info": reward_info,
        "feedback_detail": feedback_detail,
        "daily_count": daily_count,
        "milestone_reached": milestone_reached,
        "messages": []
    }
    
    # 그래프 비동기 실행
    result = await app.ainvoke(inputs)
    
    # 마지막 메시지 반환
    last_message = result["messages"][-1]
    return last_message.content
