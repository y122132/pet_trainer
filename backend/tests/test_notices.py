import asyncio
import httpx
from datetime import datetime

BASE_URL = "http://localhost:8000/v1"

async def test_notices():
    async with httpx.AsyncClient() as client:
        print("1. Testing GET /notices (should be empty initially)")
        res = await client.get(f"{BASE_URL}/notices/")
        print(f"Status: {res.status_code}, Count: {len(res.json())}")

        # Note: To test POST, we need a valid admin token. 
        # Since I can't easily get a token here without a real login, 
        # I'll focus on verifying the model and API are at least responsive.
        
        print("\nNotice system backend verification complete (Partial).")

if __name__ == "__main__":
    try:
        asyncio.run(test_notices())
    except Exception as e:
        print(f"Error connecting to server: {e}. Make sure the server is running.")
