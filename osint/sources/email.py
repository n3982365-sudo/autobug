import httpx
from api.settings import settings

def run(email: str) -> dict:
    out = {"input": email, "type": "email", "sources": [], "data": {}}
    if settings.HIBP_KEY:
        try:
            r = httpx.get(f"https://haveibeenpwned.com/api/v3/breachedaccount/{email}",
                          headers={"hibp-api-key": settings.HIBP_KEY, "user-agent": "AutoBug"},
                          timeout=15)
            if r.status_code == 200:
                out["data"]["breaches"] = r.json()
                out["sources"].append("hibp")
        except Exception:
            pass
    try:
        r = httpx.get(f"https://emailrep.io/{email}", timeout=15)
        if r.status_code == 200:
            out["data"]["emailrep"] = r.json()
            out["sources"].append("emailrep")
    except Exception:
        pass
    return out
