import asyncio
import websockets
import json

async def test_ai_match():
    user_id = 1
    # Matchmaking URL
    match_url = f"ws://localhost:8000/ws/battle/matchmaking/{user_id}"
    
    print(f"Connecting to {match_url}...")
    try:
        async with websockets.connect(match_url) as ws:
            print("Connected to Matchmaker. Sending AI_BATTLE...")
            await ws.send("AI_BATTLE")
            
            resp = await ws.recv()
            print(f"Received from Matchmaker: {resp}")
            data = json.loads(resp)
            
            if data.get("type") == "MATCH_FOUND":
                room_id = data["room_id"]
                print(f"Match Found! Room: {room_id}. Connecting to Battle Endpoint...")
                
                battle_url = f"ws://localhost:8000/ws/battle/{room_id}/{user_id}"
                async with websockets.connect(battle_url) as bws:
                    print("Connected to Battle Endpoint. Waiting for JOIN/BATTLE_START...")
                    async for msg in bws:
                        print(f"Battle Msg: {msg}")
                        msg_data = json.loads(msg)
                        if msg_data.get("type") == "BATTLE_START":
                            print("Success! Battle Started.")
                            break
            elif data.get("type") == "ERROR":
                print(f"Error from server: {data.get('message')}")
    except Exception as e:
        print(f"Test Failed: {e}")

if __name__ == "__main__":
    asyncio.run(test_ai_match())
