from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from api.routes import scans, findings, osint, plugins, reports
from api.ws import router as ws_router
from api.db import init_db

app = FastAPI(title="AutoBug", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.on_event("startup")
def _startup():
    init_db()

app.include_router(scans.router, prefix="/api/scans", tags=["scans"])
app.include_router(findings.router, prefix="/api/findings", tags=["findings"])
app.include_router(osint.router, prefix="/api/osint", tags=["osint"])
app.include_router(plugins.router, prefix="/api/plugins", tags=["plugins"])
app.include_router(reports.router, prefix="/api/reports", tags=["reports"])
app.include_router(ws_router, prefix="/ws")

@app.get("/health")
def health():
    return {"ok": True}
