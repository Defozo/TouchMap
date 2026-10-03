"""Operator-only synthetic contract diagnosis. Never prints credentials or source bytes."""
import asyncio
import os
from google import genai
from touchmap.providers import Draft,provider_schema

async def main():
    client=genai.Client(api_key=os.environ["GOOGLE_AI_STUDIO_API_KEY"])
    try:
        response=await client.aio.interactions.create(model="gemini-3.8-flash",store=False,input="Return an empty draft: title Blank, description Blank and every array empty.",response_format={"type":"text","mime_type":"application/json","schema":provider_schema()},generation_config={"thinking_level":"low","max_output_tokens":12000},timeout=30)
        print("success",response.status)
    except Exception as exc:
        print(type(exc).__name__)
        print(str(exc)[:1800])
    finally:await client.aio.aclose()

asyncio.run(main())
