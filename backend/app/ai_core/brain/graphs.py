import os
from typing import Annotated, TypedDict, Optional
from langchain_openai import ChatOpenAI
from langgraph.graph import StateGraph, END
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage
from app.ai_core.brain.prompts import (
    BASE_PERSONA, MODE_PERSONA, SUCCESS_TEMPLATE, FAIL_TEMPLATE, 
    DAILY_STREAK_ADDON, MILESTONE_ADDON, IDLE_TEMPLATE
)

# 환경변수에서 OpenAI API 키 로드
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# --- 상태(State) 정의 ---
# LangGraph의 노드 간에 전달될 데이터 구조입니다.
class AgentState(TypedDict):
    action_type: str        # 수행한 행동 (예: playing_fetch)
    current_stats: dict     # 현재 캐릭터 스탯 (호칭 결정 등에 사용)
    mode: str               # 훈련 모드 (playing, feeding, interaction)
    is_success: bool        # 행동 성공 여부
    reward_info: dict       # 보상 정보 {stat_type, value, bonus}
    feedback_detail: str    # AI 비전 피드백 (실패 원인 등)
    daily_count: int        # 오늘 수행 횟수
    milestone_reached: bool # 마일스톤(레벨업 등) 달성 여부
    messages: list          # LLM 대화 히스토리

# LLM 모델 초기화
# 비용 효율성과 속도를 위해 'gpt-4o-mini' 모델을 사용합니다.
# temperature=0.7: 적당히 창의적인 답변 생성
llm = ChatOpenAI(model="gpt-4o-mini", temperature=0.7, api_key=OPENAI_API_KEY)

# --- 노드 함수: 메시지 생성 ---
def generate_message(state: AgentState):
    """
    현재 상태(State)를 기반으로 캐릭터의 페르소나를 설정하고 반응 메시지를 생성합니다.
    """
    action = state["action_type"]
    stats = state["current_stats"]
    mode = state.get("mode", "playing")
    is_success = state.get("is_success", False)
    feedback = state.get("feedback_detail", "")
    reward = state.get("reward_info", {})
    daily_count = state.get("daily_count", 1)
    milestone_reached = state.get("milestone_reached", False)
    
    # 0. 스탯 기반 사용자 호칭 동적 결정
    user_title = "주인님" # 기본 호칭
    strength = stats.get("strength", 0)
    intelligence = stats.get("intelligence", 0)
    stamina = stats.get("stamina", 0)
    happiness = stats.get("happiness", 0)
    
    # 스탯이 높으면 호칭을 변경하여 성장을 체감하게 함
    if strength > 50: user_title = "든든한 대장님"
    elif intelligence > 50: user_title = "척척박사님"
    elif happiness > 50: user_title = "베스트 프렌드"
    elif daily_count >= 5: user_title = "열정맨"

    # 1. 모드별 페르소나(Persona) 프롬프트 설정 (prompts.py 참조)
    # 기본 페르소나에 호칭 적용
    persona_prompt = BASE_PERSONA.format(user_title=user_title)
    
    # 모드에 따른 성격 추가
    persona_prompt += MODE_PERSONA.get(mode, MODE_PERSONA["default"])

    # 2. 상황 설명(Context) 프롬프트 구성
    situation_prompt = ""
    
    if is_success:
        # 성공 시: 보상 내용과 축하 메시지
        stat_type = reward.get("stat_type", "스탯")
        stat_value = reward.get("value", 0)
        bonus = reward.get("bonus_points", 0)
        
        situation_prompt = SUCCESS_TEMPLATE.format(
            action=action, 
            stat_type=stat_type, 
            stat_value=stat_value, 
            bonus=bonus
        )
        
        # 연속 수행 문맥 추가 (꾸준함 칭찬)
        if daily_count > 1:
            situation_prompt += DAILY_STREAK_ADDON.format(daily_count=daily_count)
        
        # 마일스톤(10, 20...) 달성 시 특별 메시지
        if milestone_reached:
            situation_prompt += MILESTONE_ADDON
            
    elif action == "idle":
        # 대기(심심함) 상태
        situation_prompt = IDLE_TEMPLATE
            
    else:
        # 실패 시: 격려 및 힌트 제공
        situation_prompt = FAIL_TEMPLATE.format(
            action=action, 
            feedback=feedback
        )

    # 3. LLM 입력 메시지 구성
    # SystemMessage: 페르소나 정의 (역할 부여)
    system_msg = SystemMessage(content=f"{persona_prompt}\n\n[현재 내 상태]\n{stats}")
    # HumanMessage: 현재 상황 전달
    user_msg = HumanMessage(content=situation_prompt)
    
    messages = [system_msg, user_msg]
    
    # LLM 호출 및 응답 생성
    response = llm.invoke(messages)
    
    return {"messages": [response]}

# --- 워크플로우(Workflow) 정의 ---
# StateGraph를 사용하여 에이전트의 실행 흐름을 정의합니다.
workflow = StateGraph(AgentState)

# 노드 추가 (지금은 'agent' 단일 노드 구조)
workflow.add_node("agent", generate_message)

# 시작점 설정
workflow.set_entry_point("agent")

# 종료 지점 설정 (agent 노드 실행 후 종료)
workflow.add_edge("agent", END)

# 그래프 컴파일 (실행 가능한 앱 객체 생성)
app = workflow.compile()

# --- 외부 호출용 함수 ---
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
    LangGraph를 비동기로 실행하여 캐릭터의 반응(대사)을 생성하고 반환합니다.
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
    
    # 그래프 실행 (invoke)
    result = await app.ainvoke(inputs)
    
    # 결과에서 마지막 메시지(AIMessage)의 내용 추출
    last_message = result["messages"][-1]
    return last_message.content
