import httpx
import os
import time
from typing import Dict, Any

# Simple In-Memory Cache: {(lat, lon): {"data": ..., "ts": ...}}
# 주의: 분산 서버 환경(다중 워커)에서는 Redis 등을 캐시로 사용하는 것이 좋으나,
# 현재 단계에서는 In-Memory로 충분함. (단, 워커 재시작 시 캐시 초기화됨)
_weather_cache = {}
CACHE_DURATION = 1800 # 30분 (1800초)

async def get_weather_info(lat: float, lon: float) -> Dict[str, Any]:
    """
    OpenWeatherMap API를 사용하여 특정 좌표의 날씨 정보를 조회합니다.
    - API Key 누락 시 Fallback 값 반환
    - 30분 캐싱 적용
    - 오류 발생 시 Fallback 값 반환
    """
    api_key = os.getenv("OPENWEATHER_API_KEY")
    
    # 1. API Key Check
    if not api_key:
        print("[Weather] API Key Missing, returning default.")
        return {"main": "Clear", "temp": 20.0, "desc": "맑음 (API키 없음)"}

    # 2. Cache Check
    # 소수점 2자리에서 반올림하여 캐시 키 생성 (약 1.1km 반경)
    cache_key = (round(lat, 2), round(lon, 2))
    now = time.time()
    
    if cache_key in _weather_cache:
        cached = _weather_cache[cache_key]
        if now - cached["ts"] < CACHE_DURATION:
            # print(f"[Weather] Cache Hit: {cache_key}")
            return cached["data"]

    # 3. API Request
    url = f"https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={api_key}&units=metric&lang=kr"
    
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            data = resp.json()
            
            weather_data = {
                "main": data["weather"][0]["main"], # Rain, Clear, Clouds, Snow, Drizzle, Thunderstorm...
                "desc": data["weather"][0]["description"], # '실 비', '맑음' 등 한글 상세
                "temp": data["main"]["temp"]
            }
            
            # Save Cache
            _weather_cache[cache_key] = {"data": weather_data, "ts": now}
            print(f"[Weather] API Call Success -> {weather_data}")
            return weather_data
            
    except httpx.TimeoutException:
        print("[Weather] Timeout Error")
        return {"main": "Clear", "temp": 20.0, "desc": "맑음 (타임아웃)"}
    except Exception as e:
        print(f"[Weather] Error: {e}")
        # Fallback
        return {"main": "Clear", "temp": 20.0, "desc": "맑음 (오류)"}
