import asyncio, json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from api.redis_client import r

router = APIRouter()

@router.websocket("/scans/{scan_id}")
async def scan_ws(ws: WebSocket, scan_id: int):
    await ws.accept()
    pubsub = r.pubsub()
    pubsub.subscribe(f"scan:{scan_id}")
    try:
        for _, evt in r.xrevrange(f"scan:{scan_id}:events", count=100):
            await ws.send_text(json.dumps(evt))
            await asyncio.sleep(0.001)
        while True:
            msg = pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
            if msg:
                await ws.send_text(msg["data"])
            await asyncio.sleep(0.05)
    except WebSocketDisconnect:
        pass
    finally:
        pubsub.close()
