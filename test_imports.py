
import sys
import os
import asyncio

# 프로젝트 루트 경로를 sys.path에 추가
sys.path.append(os.path.join(os.getcwd(), 'backend'))

async def test_imports():
    try:
        print("Importing chat module...")
        from backend.app.api.v1 import chat
        print("Successfully imported chat module.")
        
        print("Importing chat_service module...")
        from backend.app.services import chat_service
        print("Successfully imported chat_service module.")
        
        print("ALL IMPORTS VALID")
    except Exception as e:
        print(f"IMPORT ERROR: {e}")

if __name__ == "__main__":
    asyncio.run(test_imports())
