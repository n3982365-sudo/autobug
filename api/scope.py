import os, json, time
from pathlib import Path

ALLOWLIST_PATH = Path(os.getenv("SCOPE_ALLOWLIST", "/app/data/scope.json"))

def _load() -> list[str]:
    if not ALLOWLIST_PATH.exists():
        return []
    try:
        return json.loads(ALLOWLIST_PATH.read_text()).get("allowed", [])
    except Exception:
        return []

def check_scope(target: str) -> tuple[bool, str]:
    if os.getenv("SCOPE_ACK_REQUIRED", "true").lower() != "true":
        return True, "guard-disabled"
    allowed = _load()
    if not allowed:
        return False, "allowlist empty"
    host = target.split("//")[-1].split("/")[0].split(":")[0].lower()
    for entry in allowed:
        e = entry.lower().lstrip("*.")
        if host == e or host.endswith("." + e):
            return True, f"matched {entry}"
    return False, f"{host} not in allowlist"

def log_scope_decision(target: str, ok: bool, reason: str):
    log = Path("/app/data/scope.log")
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a") as f:
        f.write(json.dumps({"ts": time.time(), "target": target, "ok": ok, "reason": reason}) + "\n")
