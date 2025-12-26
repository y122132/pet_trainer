import os
import random
import time
import pickle # [New] Serialization
import base64 # [New] Base64 for Redis string compatibility
from typing import Annotated, TypedDict, Optional, Literal
from langchain_openai import ChatOpenAI
from langgraph.graph import StateGraph, END, START
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage
# from langgraph.checkpoint.memory import MemorySaver # [Removed]
from app.db.database_redis import RedisManager # [New] Redis Manager
from app.ai_core.brain.prompts import (
    BASE_PERSONA, MODE_PERSONA, SUCCESS_TEMPLATE, FAIL_TEMPLATE, 
    DAILY_STREAK_ADDON, MILESTONE_ADDON, IDLE_TEMPLATE, GREETING_TEMPLATE
)

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# [New] Rule-based Templates
RULE_TEMPLATES = {
    "success": [
        "잘했어요! 아주 훌륭합니다! 🐾",
        "바로 그거예요! 완벽합니다! ✨",
        "훈련 성공! 간식을 주고 싶네요! 🍖",
        "점점 더 잘하는데요? 대단해요! 👍",
        "오늘 컨디션 최고인데요? 계속 가봅시다! 🔥"
    ],
    "fail": [
        "조금만 더 가까이 와보세요! 👀",
        "아쉽네요, 다시 한 번 해볼까요? 💪",
        "거의 다 왔어요! 힘내세요! 🐾",
        "반려동물이 잘 보이게 해주세요! 📷",
        "포기하지 마세요! 할 수 있어요! ✨"
    ]
}

# --- 상태(State) 정의 ---
class AgentState(TypedDict):
    action_type: str        
    current_stats: dict     
    mode: str               
    is_success: bool        
    reward_info: dict       
    feedback_detail: str    
    daily_count: int        
    milestone_reached: bool 
    messages: list          
    last_interaction_timestamp: float 
    is_long_absence: bool             

# LLM 모델 초기화
llm = ChatOpenAI(model="gpt-4o-mini", temperature=0.7, api_key=OPENAI_API_KEY)

# [New] Router Logic (Hybrid Filter)
def route_step(state: AgentState) -> Literal["llm_node", "rule_node"]:
    """
    상황에 따라 LLM을 쓸지, 규칙 기반 템플릿을 쓸지 결정합니다.
    """
    # 1. 특별한 이벤트 (마일스톤, 5회 단위 달성) -> LLM
    if state.get("milestone_reached", False):
        return "llm_node"
    if state.get("daily_count", 0) > 0 and state.get("daily_count", 0) % 5 == 0:
        return "llm_node"
    
    # 2. 첫 인사 / Idle / 오랜만의 접속 -> LLM
    action = state.get("action_type", "")
    if action in ["greeting", "idle"]:
        return "llm_node"
    if state.get("is_long_absence", False):
        return "llm_node"
    
    # 3. 친밀도 높음 (Happiness > 80) -> LLM (더 풍부한 감정)
    stats = state.get("current_stats", {})
    if stats.get("happiness", 0) >= 80:
        return "llm_node"
        
    # 4. 그 외 단순 반복적 성공/실패 -> Rule Based
    return "rule_node"

# [Node] LLM Message Generation
def generate_llm_message(state: AgentState):
    action = state["action_type"]
    stats = state["current_stats"]
    mode = state.get("mode", "playing")
    is_success = state.get("is_success", False)
    feedback = state.get("feedback_detail", "")
    reward = state.get("reward_info", {})
    daily_count = state.get("daily_count", 1)
    milestone_reached = state.get("milestone_reached", False)
    is_long_absence = state.get("is_long_absence", False)
    
    # 히스토리 로드 (최근 6개 대화만 유지)
    history = state.get("messages", [])
    if not history: history = []
    
    # 호칭 결정
    user_title = "주인님"
    strength = stats.get("strength", 0)
    intelligence = stats.get("intelligence", 0)
    happiness = stats.get("happiness", 0)
    
    if strength > 50: user_title = "든든한 대장님"
    elif intelligence > 50: user_title = "척척박사님"
    elif happiness > 50: user_title = "베스트 프렌드"
    
    persona_prompt = BASE_PERSONA.format(user_title=user_title)
    persona_prompt += MODE_PERSONA.get(mode, MODE_PERSONA["default"])
    
    situation_prompt = ""
    
    if is_success:
        stat_type = reward.get("stat_type", "스탯")
        stat_value = reward.get("value", 0)
        bonus = reward.get("bonus_points", 0)
        
        situation_prompt = SUCCESS_TEMPLATE.format(
            action=action, stat_type=stat_type, stat_value=stat_value, bonus=bonus
        )
        if daily_count > 1: situation_prompt += DAILY_STREAK_ADDON.format(daily_count=daily_count)
        if milestone_reached: situation_prompt += MILESTONE_ADDON
            
    elif action == "idle":
        situation_prompt = IDLE_TEMPLATE
        
    elif action == "greeting":
        # [New] 오랜만에 접속 시 특별 메시지
        if is_long_absence:
             situation_prompt = "주인님! 너무 보고 싶었어요! 어디 다녀오셨어요? 😭 배고파서 현기증 난단 말이에요..."
        else:
             situation_prompt = GREETING_TEMPLATE
            
    else:
        situation_prompt = FAIL_TEMPLATE.format(action=action, feedback=feedback)

    # 시스템 메시지 (매번 최신 상태 반영을 위해 새로 생성)
    system_msg = SystemMessage(content=f"{persona_prompt}\n\n[Stats]\n{stats}")
    user_msg = HumanMessage(content=situation_prompt)
    
    # [Context] 히스토리 포함하여 메시지 구성 (System + History + User)
    # 히스토리 중 SystemMessage나 오래된 내용은 제외하고 최근 대화만 포함
    context_messages = [system_msg] + history[-6:] + [user_msg]
    
    response = llm.invoke(context_messages)
    
    # 상태 업데이트: 히스 갱신
    new_history = history + [user_msg, response]
    # 너무 길어지지 않게 관리 (최대 20개)
    if len(new_history) > 20:
        new_history = new_history[-20:]
        
    return {"messages": new_history}

# [Node] Rule-based Message Generation
def generate_rule_message(state: AgentState):
    is_success = state.get("is_success", False)
    key = "success" if is_success else "fail"
    templates = RULE_TEMPLATES.get(key, RULE_TEMPLATES["success"])
    msg = random.choice(templates)
    
    # Rule 기반 메시지는 히스토리에 굳이 쌓지 않거나, 쌓더라도 간단하게 처리
    # 여기서는 대화 맥락 유지를 위해 쌓는 것으로 결정
    history = state.get("messages", [])
    if not history: history = []
    
    ai_msg = AIMessage(content=msg)
    new_history = history + [ai_msg]
    if len(new_history) > 20: new_history = new_history[-20:]
    
    return {"messages": new_history}

# --- 워크플로우(Workflow) 정의 ---
# memory = MemorySaver() # [Removed]

workflow = StateGraph(AgentState)
workflow.add_node("llm_node", generate_llm_message)
workflow.add_node("rule_node", generate_rule_message)

# 조건부 엣지 추가 (Router)
workflow.add_conditional_edges(
    START,
    route_step,
    {
        "llm_node": "llm_node",
        "rule_node": "rule_node"
    }
)

workflow.add_edge("llm_node", END)
workflow.add_edge("rule_node", END)

# Checkpointer 없이 컴파일 (Manual State Management)
app = workflow.compile()

# --- 외부 호출용 함수 ---
async def get_character_response(
    user_id: int, # [New] User ID for Thread handling
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
    Redis를 사용하여 대화 맥락(State)을 로드하고 LangGraph를 실행한 뒤 결과를 저장합니다.
    """
    
    # 1. Redis에서 상태 로드
    client = RedisManager.get_client()
    redis_key = f"brain_state:{user_id}"
    
    saved_state = {}
    is_long_absence = False
    
    try:
        data = await client.get(redis_key)
        if data:
            # Base64 decode string to bytes, then unpickle
            saved_state = pickle.loads(base64.b64decode(data))
            last_ts = saved_state.get("last_interaction_timestamp", 0)
            if last_ts > 0 and (time.time() - last_ts > 86400):
                is_long_absence = True
    except Exception as e:
        print(f"[Brain] Redis Load Error: {e}")
        saved_state = {}

    # 2. 입력 데이터 구성 (기존 상태 + 새로운 입력)
    inputs = {
        "action_type": action_type,
        "current_stats": current_stats,
        "mode": mode,
        "is_success": is_success,
        "reward_info": reward_info,
        "feedback_detail": feedback_detail,
        "daily_count": daily_count,
        "milestone_reached": milestone_reached,
        "last_interaction_timestamp": time.time(),
        "is_long_absence": is_long_absence,
        "messages": saved_state.get("messages", []) # 기존 대화 히스토리 주입
    }
    
    # 3. 그래프 실행
    result = await app.ainvoke(inputs)
    
    # 4. Redis에 최신 상태 저장
    try:
        # 결과 전체를 저장 (Result는 AgentState 구조)
        # Pickle bytes -> Base64 bytes -> String
        serialized_data = base64.b64encode(pickle.dumps(result)).decode('utf-8')
        await client.set(redis_key, serialized_data)
    except Exception as e:
        print(f"[Brain] Redis Save Error: {e}")
    
    last_message = result["messages"][-1]
    return last_message.content
