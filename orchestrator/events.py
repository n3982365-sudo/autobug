import json, time
from api.redis_client import r

def emit(scan_id: int, node: str, level: str = "info", payload: dict | None = None):
    evt = {"scan_id": scan_id, "node": node, "level": level, "ts": time.time(), "payload": payload or {}}
    r.xadd(f"scan:{scan_id}:events", evt, maxlen=10000)
    r.publish(f"scan:{scan_id}", json.dumps(evt))
