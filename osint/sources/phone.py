import httpx

def run(phone: str) -> dict:
    out = {"input": phone, "type": "phone", "sources": [], "data": {}}
    try:
        r = httpx.get(f"https://api.numlookupapi.com/v1/validate/{phone}", timeout=15)
        if r.status_code == 200:
            out["data"]["numlookup"] = r.json()
            out["sources"].append("numlookup")
    except Exception:
        pass
    return out
