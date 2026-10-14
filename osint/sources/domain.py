import httpx

def run(domain: str) -> dict:
    out = {"input": domain, "type": "domain", "sources": [], "data": {}}
    try:
        r = httpx.get(f"https://crt.sh/?q=%25.{domain}&output=json", timeout=20)
        if r.status_code == 200:
            subs = sorted({e["name_value"] for e in r.json()})
            out["data"]["subdomains"] = subs[:500]
            out["sources"].append("crt.sh")
    except Exception:
        pass
    try:
        r = httpx.get(f"https://dns.google/resolve?name={domain}&type=MX", timeout=10)
        if r.status_code == 200:
            out["data"]["mx"] = r.json().get("Answer", [])
            out["sources"].append("google-dns")
    except Exception:
        pass
    return out
