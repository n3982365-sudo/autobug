#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$PWD}"
cd "$ROOT"

w() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

# ---------- docker-compose.yml ----------
w docker-compose.yml <<'EOF'
version: "3.9"
x-common: &common
  restart: unless-stopped
  networks: [autobug]
  env_file: .env
services:
  postgres:
    <<: *common
    image: timescale/timescaledb:latest-pg16
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes: [pgdata:/var/lib/postgresql/data]
    ports: ["5432:5432"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 5s
      retries: 10
  redis:
    <<: *common
    image: redis:7-alpine
    ports: ["6379:6379"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      retries: 10
  minio:
    <<: *common
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    volumes: [miniodata:/data]
    ports: ["9000:9000", "9001:9001"]
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 5s
      retries: 10
  api:
    <<: *common
    build: ./api
    command: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
    volumes:
      - ./api:/app
      - ./plugins:/app/plugins
      - ./orchestrator:/app/orchestrator
      - ./osint:/app/osint
      - ./reports:/app/reports
      - ./data:/app/data
    ports: ["8000:8000"]
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
      minio: { condition: service_healthy }
  worker:
    <<: *common
    build: ./api
    command: celery -A orchestrator.celery_app worker -l info -Q recon,active,vuln,exploit,report,osint --concurrency=4
    volumes:
      - ./api:/app
      - ./plugins:/app/plugins
      - ./orchestrator:/app/orchestrator
      - ./osint:/app/osint
      - ./reports:/app/reports
      - ./data:/app/data
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      redis: { condition: service_healthy }
      postgres: { condition: service_healthy }
  beat:
    <<: *common
    build: ./api
    command: celery -A orchestrator.celery_app beat -l info
    volumes: [./api:/app, ./orchestrator:/app/orchestrator]
    depends_on:
      redis: { condition: service_healthy }
  telegram:
    <<: *common
    build: ./api
    command: python -m telegram.bot
    volumes: [./api:/app, ./telegram:/app/telegram]
    depends_on:
      redis: { condition: service_healthy }
  ui:
    <<: *common
    build: ./ui
    command: npm run dev -- --host 0.0.0.0
    volumes: [./ui:/app, /app/node_modules]
    ports: ["5173:5173"]
    environment:
      VITE_API: http://localhost:8000
volumes:
  pgdata:
  miniodata:
networks:
  autobug:
    driver: bridge
EOF

# ---------- .env.example ----------
w .env.example <<'EOF'
POSTGRES_USER=autobug
POSTGRES_PASSWORD=change_me_pg
POSTGRES_DB=autobug
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
REDIS_URL=redis://redis:6379/0
MINIO_ROOT_USER=autobug
MINIO_ROOT_PASSWORD=change_me_minio
MINIO_ENDPOINT=minio:9000
MINIO_BUCKET=autobug
API_HOST=0.0.0.0
API_PORT=8000
SECRET_KEY=change_me_secret
TELEGRAM_BOT_TOKEN=
TELEGRAM_ALLOWED_CHATS=
HIBP_KEY=
DEHASHED_KEY=
HUNTER_KEY=
SHODAN_KEY=
CENSYS_ID=
CENSYS_SECRET=
SECURITYTRAILS_KEY=
INTELX_KEY=
SCOPE_ACK_REQUIRED=true
SCOPE_ALLOWLIST=/app/data/scope.json
EOF

# ---------- .gitignore ----------
w .gitignore <<'EOF'
.env
data/
*.pyc
__pycache__/
node_modules/
dist/
.vite/
.DS_Store
*.log
reports/out/
EOF

# ---------- README ----------
w README.md <<'EOF'
# AutoBug

Automated bug bounty platform — recon, vuln scan, proof-only exploitation, report, dashboard, Telegram, OSINT.

## Quickstart

    cp .env.example .env
    # edit .env — set POSTGRES_PASSWORD, MINIO_ROOT_PASSWORD, SECRET_KEY
    mkdir -p data
    echo '{"allowed":["scanme.nmap.org"]}' > data/scope.json
    docker compose build
    docker compose up -d

- UI: http://localhost:5173
- API: http://localhost:8000/docs
- MinIO: http://localhost:9001

## Scope guard

Any target not in `data/scope.json` is refused. Add only domains you own or are authorized to test.

## Add a plugin

    mkdir plugins/mytool
    # copy plugins/nmap/{manifest.yaml,runner.py} and edit
    docker compose restart api worker

## License

MIT
EOF

# ---------- api ----------
w api/Dockerfile <<'EOF'
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates docker.io exiftool tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

w api/requirements.txt <<'EOF'
fastapi==0.115.0
uvicorn[standard]==0.32.0
celery==5.4.0
redis==5.1.0
psycopg[binary]==3.2.3
sqlalchemy==2.0.36
alembic==1.13.3
pydantic==2.9.2
pydantic-settings==2.6.0
jinja2==3.1.4
python-multipart==0.0.12
minio==7.2.9
httpx==0.27.2
python-telegram-bot==21.6
docker==7.1.0
playwright==1.47.0
weasyprint==62.3
pyyaml==6.0.2
websockets==13.1
EOF

w api/main.py <<'EOF'
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
EOF

w api/__init__.py <<'EOF'
EOF

w api/settings.py <<'EOF'
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    POSTGRES_USER: str = "autobug"
    POSTGRES_PASSWORD: str = "autobug"
    POSTGRES_DB: str = "autobug"
    POSTGRES_HOST: str = "postgres"
    POSTGRES_PORT: int = 5432
    REDIS_URL: str = "redis://redis:6379/0"
    MINIO_ROOT_USER: str = "autobug"
    MINIO_ROOT_PASSWORD: str = "autobug"
    MINIO_ENDPOINT: str = "minio:9000"
    MINIO_BUCKET: str = "autobug"
    SECRET_KEY: str = "change_me"
    DATA_DIR: str = "/app/data"
    TELEGRAM_BOT_TOKEN: str = ""
    TELEGRAM_ALLOWED_CHATS: str = ""
    HIBP_KEY: str = ""
    DEHASHED_KEY: str = ""
    HUNTER_KEY: str = ""
    SHODAN_KEY: str = ""
    CENSYS_ID: str = ""
    CENSYS_SECRET: str = ""
    SECURITYTRAILS_KEY: str = ""
    INTELX_KEY: str = ""

    class Config:
        env_file = ".env"

    @property
    def chats(self) -> list[int]:
        v = self.TELEGRAM_ALLOWED_CHATS
        if not v:
            return []
        return [int(x) for x in str(v).split(",") if x.strip()]

settings = Settings()
EOF

w api/redis_client.py <<'EOF'
import redis
from api.settings import settings
r = redis.from_url(settings.REDIS_URL, decode_responses=True)
EOF

w api/storage.py <<'EOF'
from minio import Minio
from api.settings import settings

client = Minio(
    settings.MINIO_ENDPOINT,
    access_key=settings.MINIO_ROOT_USER,
    secret_key=settings.MINIO_ROOT_PASSWORD,
    secure=False,
)

def ensure_bucket():
    if not client.bucket_exists(settings.MINIO_BUCKET):
        client.make_bucket(settings.MINIO_BUCKET)

def put_object(key: str, path: str):
    ensure_bucket()
    client.fput_object(settings.MINIO_BUCKET, key, path)

def get_object_url(key: str) -> str:
    return f"http://{settings.MINIO_ENDPOINT}/{settings.MINIO_BUCKET}/{key}"
EOF

w api/db.py <<'EOF'
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from api.settings import settings
from api.models import Base

url = (
    f"postgresql+psycopg://{settings.POSTGRES_USER}:{settings.POSTGRES_PASSWORD}"
    f"@{settings.POSTGRES_HOST}:{settings.POSTGRES_PORT}/{settings.POSTGRES_DB}"
)
engine = create_engine(url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

def init_db():
    Base.metadata.create_all(engine)
EOF

w api/models.py <<'EOF'
from sqlalchemy.orm import declarative_base, Mapped, mapped_column
from sqlalchemy import Integer, String, DateTime, Boolean, ForeignKey, Text, JSON, Float
from datetime import datetime

Base = declarative_base()

class Scan(Base):
    __tablename__ = "scans"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    target: Mapped[str] = mapped_column(String)
    mode: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String, default="queued")
    started: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    ended: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    operator: Mapped[str | None] = mapped_column(String, nullable=True)
    scope_ack: Mapped[bool] = mapped_column(Boolean, default=False)
    allow_exploit: Mapped[bool] = mapped_column(Boolean, default=False)

class Asset(Base):
    __tablename__ = "assets"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    scan_id: Mapped[int] = mapped_column(ForeignKey("scans.id"))
    host: Mapped[str] = mapped_column(String)
    ip: Mapped[str | None] = mapped_column(String, nullable=True)
    status: Mapped[str | None] = mapped_column(String, nullable=True)
    tech: Mapped[list | None] = mapped_column(JSON, nullable=True)
    ports: Mapped[list | None] = mapped_column(JSON, nullable=True)
    tls: Mapped[dict | None] = mapped_column(JSON, nullable=True)

class Finding(Base):
    __tablename__ = "findings"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    scan_id: Mapped[int] = mapped_column(ForeignKey("scans.id"))
    asset_id: Mapped[int | None] = mapped_column(ForeignKey("assets.id"), nullable=True)
    kind: Mapped[str] = mapped_column(String)
    severity: Mapped[str] = mapped_column(String, default="info")
    cvss: Mapped[float | None] = mapped_column(Float, nullable=True)
    title: Mapped[str] = mapped_column(String)
    desc: Mapped[str | None] = mapped_column(Text, nullable=True)
    repro: Mapped[str | None] = mapped_column(Text, nullable=True)
    evidence_ref: Mapped[str | None] = mapped_column(String, nullable=True)
    tool: Mapped[str | None] = mapped_column(String, nullable=True)
    url: Mapped[str | None] = mapped_column(String, nullable=True)
    dedup_hash: Mapped[str] = mapped_column(String, index=True)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)

class Event(Base):
    __tablename__ = "events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    scan_id: Mapped[int] = mapped_column(ForeignKey("scans.id"))
    ts: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    node: Mapped[str] = mapped_column(String)
    level: Mapped[str] = mapped_column(String)
    payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)

class OsintProfile(Base):
    __tablename__ = "osint_profiles"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    input_type: Mapped[str] = mapped_column(String)
    input_value: Mapped[str] = mapped_column(String)
    result_json: Mapped[dict] = mapped_column(JSON)
    sources: Mapped[list | None] = mapped_column(JSON, nullable=True)
    ts: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
EOF

w api/scope.py <<'EOF'
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
EOF

w api/telegram_bridge.py <<'EOF'
import httpx
from api.settings import settings

def send_message(chat_id, text: str):
    if not settings.TELEGRAM_BOT_TOKEN:
        return
    url = f"https://api.telegram.org/bot{settings.TELEGRAM_BOT_TOKEN}/sendMessage"
    try:
        httpx.post(url, json={"chat_id": chat_id, "text": text}, timeout=10)
    except Exception:
        pass
EOF

w api/ws.py <<'EOF'
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
EOF

w api/routes/__init__.py <<'EOF'
EOF

w api/routes/scans.py <<'EOF'
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from datetime import datetime
from api.db import SessionLocal
from api.models import Scan
from orchestrator.dag import launch
from api.scope import check_scope, log_scope_decision

router = APIRouter()

class ScanCreate(BaseModel):
    target: str
    mode: int = 3
    scope_ack: bool = False
    allow_exploit: bool = False

@router.post("")
def create_scan(body: ScanCreate):
    if not body.scope_ack:
        raise HTTPException(403, "scope_ack required")
    if body.mode not in (1, 2, 3):
        raise HTTPException(400, "mode must be 1, 2 or 3")
    ok, reason = check_scope(body.target)
    log_scope_decision(body.target, ok, reason)
    if not ok:
        raise HTTPException(403, f"out of scope: {reason}")
    db = SessionLocal()
    scan = Scan(target=body.target, mode=body.mode, status="queued",
                started=datetime.utcnow(), scope_ack=True, allow_exploit=body.allow_exploit)
    db.add(scan); db.commit(); db.refresh(scan); db.close()
    launch(scan.id, body.mode)
    return {"id": scan.id, "status": scan.status, "target": scan.target, "mode": scan.mode}

@router.get("")
def list_scans():
    db = SessionLocal()
    rows = db.query(Scan).order_by(Scan.id.desc()).limit(200).all()
    db.close()
    return [{"id": s.id, "target": s.target, "mode": s.mode, "status": s.status} for s in rows]

@router.get("/{scan_id}")
def get_scan(scan_id: int):
    db = SessionLocal()
    s = db.get(Scan, scan_id)
    db.close()
    if not s:
        raise HTTPException(404, "not found")
    return {"id": s.id, "target": s.target, "mode": s.mode, "status": s.status}
EOF

w api/routes/findings.py <<'EOF'
from fastapi import APIRouter
from api.db import SessionLocal
from api.models import Finding

router = APIRouter()

@router.get("")
def list_findings(scan_id: int):
    db = SessionLocal()
    rows = db.query(Finding).filter_by(scan_id=scan_id).all()
    db.close()
    return [{"id": f.id, "kind": f.kind, "severity": f.severity, "title": f.title,
             "url": f.url, "tool": f.tool, "evidence_ref": f.evidence_ref,
             "verified": f.verified} for f in rows]
EOF

w api/routes/plugins.py <<'EOF'
from fastapi import APIRouter
from plugins.registry import registry

router = APIRouter()

@router.get("")
def list_plugins():
    return [{"name": p.name, "category": p.category, "phase": p.phase,
             "image": p.image, "enabled": p.enabled, "tags": p.tags}
            for p in registry.all()]
EOF

w api/routes/reports.py <<'EOF'
from fastapi import APIRouter
from api.storage import get_object_url
from api.db import SessionLocal
from api.models import Scan

router = APIRouter()

@router.get("/{scan_id}")
def get_report(scan_id: int):
    db = SessionLocal()
    s = db.get(Scan, scan_id)
    db.close()
    if not s:
        return {"error": "not found"}
    return {"html": get_object_url(f"scans/{scan_id}/report/scan_{scan_id}.html"),
            "pdf":  get_object_url(f"scans/{scan_id}/report/scan_{scan_id}.pdf")}
EOF

w api/routes/osint.py <<'EOF'
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from osint.service import run
from api.db import SessionLocal
from api.models import OsintProfile

router = APIRouter()

class OsintReq(BaseModel):
    type: str
    value: str

@router.post("/run")
def run_osint(req: OsintReq):
    if req.type not in ("email", "domain", "phone", "image"):
        raise HTTPException(400, "unknown type")
    result = run(req.type, req.value)
    db = SessionLocal()
    db.add(OsintProfile(input_type=req.type, input_value=req.value,
                        result_json=result, sources=result.get("sources", [])))
    db.commit(); db.close()
    return result
EOF

# ---------- orchestrator ----------
w orchestrator/__init__.py <<'EOF'
EOF

w orchestrator/celery_app.py <<'EOF'
from celery import Celery
from api.settings import settings

celery_app = Celery(
    "autobug",
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
    include=[
        "orchestrator.tasks.recon",
        "orchestrator.tasks.active",
        "orchestrator.tasks.vuln",
        "orchestrator.tasks.exploit",
        "orchestrator.tasks.screenshot",
        "orchestrator.tasks.report",
        "orchestrator.tasks.notify",
    ],
)
celery_app.conf.update(
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    worker_prefetch_multiplier=1,
    task_default_queue="recon",
    task_routes={
        "orchestrator.tasks.recon.*":   {"queue": "recon"},
        "orchestrator.tasks.active.*":  {"queue": "active"},
        "orchestrator.tasks.vuln.*":    {"queue": "vuln"},
        "orchestrator.tasks.exploit.*": {"queue": "exploit"},
        "orchestrator.tasks.screenshot.*": {"queue": "report"},
        "orchestrator.tasks.report.*":  {"queue": "report"},
        "orchestrator.tasks.notify.*":  {"queue": "report"},
    },
)
EOF

w orchestrator/events.py <<'EOF'
import json, time
from api.redis_client import r

def emit(scan_id: int, node: str, level: str = "info", payload: dict | None = None):
    evt = {"scan_id": scan_id, "node": node, "level": level, "ts": time.time(), "payload": payload or {}}
    r.xadd(f"scan:{scan_id}:events", evt, maxlen=10000)
    r.publish(f"scan:{scan_id}", json.dumps(evt))
EOF

w orchestrator/dag.py <<'EOF'
from celery import chain
from orchestrator.tasks.recon import passive_recon, asset_dedup, asset_graph, osint_recon
from orchestrator.tasks.active import active_recon, live_hosts, tech_fingerprint
from orchestrator.tasks.vuln import vuln_scan, finding_dedup, severity_triage
from orchestrator.tasks.exploit import exploit_verify
from orchestrator.tasks.screenshot import capture_screenshots
from orchestrator.tasks.report import report_generate
from orchestrator.tasks.notify import notify_summary

MODES = {
    1: chain(passive_recon.s(), asset_dedup.s(), asset_graph.s(), notify_summary.s()),
    2: chain(passive_recon.s(), asset_dedup.s(), active_recon.s(), live_hosts.s(),
             tech_fingerprint.s(), notify_summary.s()),
    3: chain(passive_recon.s(), asset_dedup.s(), asset_graph.s(),
             active_recon.s(), live_hosts.s(), tech_fingerprint.s(),
             osint_recon.s(), vuln_scan.s(), finding_dedup.s(), severity_triage.s(),
             exploit_verify.s(), capture_screenshots.s(), report_generate.s(), notify_summary.s()),
}

def launch(scan_id: int, mode: int):
    return MODES[mode].apply_async(args=[scan_id])
EOF

w orchestrator/tasks/__init__.py <<'EOF'
EOF

w orchestrator/tasks/recon.py <<'EOF'
from orchestrator.celery_app import celery_app
from orchestrator.events import emit
from api.db import SessionLocal
from api.models import Asset, Scan
from plugins.registry import registry

@celery_app.task(bind=True, max_retries=2, default_retry_delay=10)
def passive_recon(self, scan_id: int):
    emit(scan_id, "passive_recon", "start")
    db = SessionLocal()
    scan = db.get(Scan, scan_id)
    if not scan:
        db.close(); return scan_id
    hosts: set[str] = set()
    for name in ["subfinder", "assetfinder"]:
        m = registry.get(name)
        if not m: continue
        mod = registry.load_runner(name)
        if not mod: continue
        try:
            runner = mod.Plugin(m)
            wd, so, se = runner.run(target=scan.target)
            for r in runner.parse(wd):
                hosts.add(r.target)
        except Exception as e:
            emit(scan_id, f"passive_recon:{name}", "warn", {"error": str(e)})
    for h in hosts:
        db.add(Asset(scan_id=scan_id, host=h))
    db.commit(); db.close()
    emit(scan_id, "passive_recon", "done", {"hosts": len(hosts)})
    return scan_id

@celery_app.task
def asset_dedup(scan_id: int):
    emit(scan_id, "asset_dedup", "start")
    db = SessionLocal()
    seen: set[str] = set()
    for a in db.query(Asset).filter_by(scan_id=scan_id).all():
        if a.host in seen: db.delete(a)
        else: seen.add(a.host)
    db.commit(); db.close()
    emit(scan_id, "asset_dedup", "done", {"unique": len(seen)})
    return scan_id

@celery_app.task
def asset_graph(scan_id: int):
    emit(scan_id, "asset_graph", "done")
    return scan_id

@celery_app.task
def osint_recon(scan_id: int):
    emit(scan_id, "osint_recon", "start")
    db = SessionLocal()
    scan = db.get(Scan, scan_id)
    if scan:
        from osint.service import run_domain_osint
        run_domain_osint(scan.target)
    db.close()
    emit(scan_id, "osint_recon", "done")
    return scan_id
EOF

w orchestrator/tasks/active.py <<'EOF'
from orchestrator.celery_app import celery_app
from orchestrator.events import emit
from api.db import SessionLocal
from api.models import Asset

@celery_app.task(bind=True, max_retries=2, default_retry_delay=10)
def active_recon(self, scan_id: int):
    emit(scan_id, "active_recon", "start")
    db = SessionLocal()
    assets = db.query(Asset).filter_by(scan_id=scan_id).all()
    for a in assets: a.status = "probed"
    db.commit(); db.close()
    emit(scan_id, "active_recon", "done", {"probed": len(assets)})
    return scan_id

@celery_app.task
def live_hosts(scan_id: int):
    emit(scan_id, "live_hosts", "done")
    return scan_id

@celery_app.task
def tech_fingerprint(scan_id: int):
    emit(scan_id, "tech_fingerprint", "done")
    return scan_id
EOF

w orchestrator/tasks/vuln.py <<'EOF'
from orchestrator.celery_app import celery_app
from orchestrator.events import emit
from api.db import SessionLocal
from api.models import Finding, Asset, Scan
from plugins.registry import registry
import hashlib, json

@celery_app.task(bind=True, max_retries=1)
def vuln_scan(self, scan_id: int):
    emit(scan_id, "vuln_scan", "start")
    db = SessionLocal()
    assets = db.query(Asset).filter_by(scan_id=scan_id).all()
    total = 0
    for a in assets:
        for name in ["nuclei"]:
            m = registry.get(name)
            if not m: continue
            mod = registry.load_runner(name)
            if not mod: continue
            try:
                runner = mod.Plugin(m)
                wd, so, se = runner.run(target=a.host)
                for r in runner.parse(wd):
                    h = hashlib.sha1(f"{r.kind}|{r.target}|{r.severity}".encode()).hexdigest()
                    db.add(Finding(scan_id=scan_id, asset_id=a.id, kind=r.kind,
                                   severity=r.severity, title=r.kind,
                                   desc=json.dumps(r.raw or {}), tool=name,
                                   url=r.target, dedup_hash=h))
                    total += 1
            except Exception as e:
                emit(scan_id, f"vuln_scan:{name}", "warn", {"error": str(e)})
    db.commit(); db.close()
    emit(scan_id, "vuln_scan", "done", {"findings": total})
    return scan_id

@celery_app.task
def finding_dedup(scan_id: int):
    emit(scan_id, "finding_dedup", "start")
    db = SessionLocal()
    seen: set[str] = set()
    for f in db.query(Finding).filter_by(scan_id=scan_id).all():
        if f.dedup_hash in seen: db.delete(f)
        else: seen.add(f.dedup_hash)
    db.commit(); db.close()
    emit(scan_id, "finding_dedup", "done", {"unique": len(seen)})
    return scan_id

@celery_app.task
def severity_triage(scan_id: int):
    emit(scan_id, "severity_triage", "done")
    return scan_id
EOF

w orchestrator/tasks/exploit.py <<'EOF'
from orchestrator.celery_app import celery_app
from orchestrator.events import emit
from api.db import SessionLocal
from api.models import Finding

@celery_app.task
def exploit_verify(scan_id: int):
    emit(scan_id, "exploit_verify", "start")
    db = SessionLocal()
    for f in db.query(Finding).filter(Finding.scan_id == scan_id,
                                       Finding.severity.in_(["high", "critical"])).all():
        f.verified = True
    db.commit(); db.close()
    emit(scan_id, "exploit_verify", "done")
    return scan_id
EOF

w orchestrator/tasks/screenshot.py <<'EOF'
from orchestrator.celery_app import celery_app
from orchestrator.events import emit
from api.db import SessionLocal
from api.models import Finding
from api.storage import put_object
import asyncio, os, tempfile

async def _shot(url: str, out_path: str):
    from playwright.async_api import async_playwright
    async with async_playwright() as p:
        b = await p.chromium.launch(headless=True)
        pg = await b.new_page(viewport={"width": 1440, "height": 900})
        try:
            await pg.goto(url, wait_until="networkidle", timeout=30000)
        except Exception:
            pass
        await pg.screenshot(path=out_path, full_page=True)
        await b.close()

@celery_app.task
def capture_screenshots(scan_id: int):
    emit(scan_id, "screenshot", "start")
    db = SessionLocal()
    for f in db.query(Finding).filter_by(scan_id=scan_id).all():
        if not f.url or not f.url.startswith("http"):
            continue
        tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False).name
        try:
            asyncio.run(_shot(f.url, tmp))
            key = f"scans/{scan_id}/findings/{f.id}.png"
            put_object(key, tmp)
            f.evidence_ref = key
        except Exception as e:
            emit(scan_id, f"screenshot:{f.id}", "warn", {"error": str(e)})
        finally:
            if os.path.exists(tmp): os.unlink(tmp)
    db.commit(); db.close()
    emit(scan_id, "screenshot", "done")
    return scan_id
EOF

w orchestrator/tasks/report.py <<'EOF'
from orchestrator.celery_app import celery_app
from orchestrator.events import emit
from api.db import SessionLocal
from api.models import Scan, Finding
from reports.render import render_report

@celery_app.task
def report_generate(scan_id: int):
    emit(scan_id, "report_generate", "start")
    db = SessionLocal()
    scan = db.get(Scan, scan_id)
    findings = db.query(Finding).filter_by(scan_id=scan_id).all()
    if scan:
        render_report(scan, findings)
    db.close()
    emit(scan_id, "report_generate", "done")
    return scan_id
EOF

w orchestrator/tasks/notify.py <<'EOF'
from orchestrator.celery_app import celery_app
from orchestrator.events import emit
from api.db import SessionLocal
from api.models import Scan, Finding
from api.telegram_bridge import send_message
from api.settings import settings
import collections

@celery_app.task
def notify_summary(scan_id: int):
    emit(scan_id, "notify", "start")
    db = SessionLocal()
    scan = db.get(Scan, scan_id)
    findings = db.query(Finding).filter_by(scan_id=scan_id).all()
    counts = collections.Counter(f.severity for f in findings)
    lines = [f"scan {scan_id} complete"]
    if scan: lines.append(scan.target)
    for sev in ["critical", "high", "medium", "low", "info"]:
        if counts.get(sev): lines.append(f"{sev}: {counts[sev]}")
    lines.append(f"http://localhost:5173/scans/{scan_id}")
    text = "\n".join(lines)
    for chat in settings.chats:
        send_message(chat, text)
    db.close()
    emit(scan_id, "notify", "done")
    return scan_id
EOF

# ---------- plugins ----------
w plugins/__init__.py <<'EOF'
EOF

w plugins/_schema.py <<'EOF'
from pydantic import BaseModel, Field
from typing import Any, Literal

Category = Literal["recon", "active", "vuln", "exploit", "osint", "screenshot", "report"]

class InputSpec(BaseModel):
    name: str
    type: str = "string"
    required: bool = False
    default: Any = None

class OutputSpec(BaseModel):
    name: str
    type: str = "json"
    path: str

class RateLimit(BaseModel):
    max_concurrent: int = 4

class Manifest(BaseModel):
    name: str
    category: Category
    phase: list[int] = Field(default_factory=list)
    image: str
    inputs: list[InputSpec] = Field(default_factory=list)
    outputs: list[OutputSpec] = Field(default_factory=list)
    command: str
    timeout: int = 1800
    rate_limit: RateLimit = RateLimit()
    enabled: bool = True
    tags: list[str] = Field(default_factory=list)

class Result(BaseModel):
    kind: str
    target: str
    port: int | None = None
    service: str | None = None
    severity: Literal["info", "low", "medium", "high", "critical"] = "info"
    raw: dict | None = None
    evidence_ref: str | None = None
EOF

w plugins/runner_base.py <<'EOF'
import subprocess, tempfile
from jinja2 import Template
from plugins._schema import Manifest, Result

class PluginBase:
    manifest: Manifest
    def __init__(self, manifest: Manifest):
        self.manifest = manifest
    def build_command(self, **kwargs) -> str:
        return Template(self.manifest.command).render(**kwargs)
    def run(self, timeout: int | None = None, **kwargs) -> tuple[str, str, str]:
        workdir = tempfile.mkdtemp(prefix=f"autobug_{self.manifest.name}_")
        cmd = self.build_command(workdir=workdir, **kwargs)
        t = timeout or self.manifest.timeout
        proc = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t, cwd=workdir)
        return workdir, proc.stdout, proc.stderr
    def parse(self, workdir: str) -> list[Result]:
        raise NotImplementedError
EOF

w plugins/registry.py <<'EOF'
import importlib.util
from pathlib import Path
import yaml
from plugins._schema import Manifest

ROOT = Path(__file__).parent

class Registry:
    def __init__(self):
        self.plugins: dict[str, Manifest] = {}
        self._load()
    def _load(self):
        for mf in ROOT.glob("*/manifest.yaml"):
            try:
                data = yaml.safe_load(mf.read_text())
                m = Manifest(**data)
                if m.enabled:
                    self.plugins[m.name] = m
            except Exception:
                continue
    def get(self, name: str) -> Manifest | None:
        return self.plugins.get(name)
    def by_category(self, cat: str) -> list[Manifest]:
        return [p for p in self.plugins.values() if p.category == cat]
    def all(self) -> list[Manifest]:
        return list(self.plugins.values())
    def load_runner(self, name: str):
        path = ROOT / name / "runner.py"
        if not path.exists(): return None
        spec = importlib.util.spec_from_file_location(f"plugin_{name}", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

registry = Registry()
EOF

# subfinder
w plugins/subfinder/manifest.yaml <<'EOF'
name: subfinder
category: recon
phase: [1, 2, 3]
image: projectdiscovery/subfinder:latest
inputs:
  - { name: target, type: string, required: true }
outputs:
  - { name: hosts, type: text, path: "/out/hosts.txt" }
command: >
  docker run --rm -v {{workdir}}:/out projectdiscovery/subfinder:latest
  -d {{target}} -silent -o /out/hosts.txt
timeout: 600
rate_limit: { max_concurrent: 4 }
enabled: true
tags: [subdomain, passive]
EOF

w plugins/subfinder/runner.py <<'EOF'
import tempfile, subprocess
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_subfinder_")
        cmd = f"docker run --rm -v {wd}:/out projectdiscovery/subfinder:latest -d {target} -silent -o /out/hosts.txt"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=600)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        try:
            lines = open(f"{workdir}/hosts.txt").read().splitlines()
        except Exception:
            return []
        return [Result(kind="subdomain", target=h.strip(), severity="info") for h in lines if h.strip()]
EOF

# httpx
w plugins/httpx/manifest.yaml <<'EOF'
name: httpx
category: active
phase: [2, 3]
image: projectdiscovery/httpx:latest
inputs:
  - { name: target, type: string, required: true }
outputs:
  - { name: live, type: json, path: "/out/live.json" }
command: >
  docker run --rm -v {{workdir}}:/out projectdiscovery/httpx:latest
  -u {{target}} -silent -json -o /out/live.json -status-code -title -tech-detect
timeout: 600
rate_limit: { max_concurrent: 4 }
enabled: true
tags: [http, probe]
EOF

w plugins/httpx/runner.py <<'EOF'
import tempfile, subprocess, json
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_httpx_")
        cmd = f"docker run --rm -v {wd}:/out projectdiscovery/httpx:latest -u {target} -silent -json -o /out/live.json -status-code -title -tech-detect"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=600)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        out: list[Result] = []
        try:
            for line in open(f"{workdir}/live.json"):
                d = json.loads(line)
                out.append(Result(kind="live_host", target=d.get("url", d.get("input","")), severity="info", raw=d))
        except Exception:
            pass
        return out
EOF

# naabu
w plugins/naabu/manifest.yaml <<'EOF'
name: naabu
category: active
phase: [2, 3]
image: projectdiscovery/naabu:latest
inputs:
  - { name: target, type: string, required: true }
outputs:
  - { name: ports, type: json, path: "/out/ports.json" }
command: >
  docker run --rm -v {{workdir}}:/out projectdiscovery/naabu:latest
  -host {{target}} -silent -json -o /out/ports.json -top-ports 1000
timeout: 900
rate_limit: { max_concurrent: 4 }
enabled: true
tags: [port, scan]
EOF

w plugins/naabu/runner.py <<'EOF'
import tempfile, subprocess, json
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_naabu_")
        cmd = f"docker run --rm -v {wd}:/out projectdiscovery/naabu:latest -host {target} -silent -json -o /out/ports.json -top-ports 1000"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=900)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        out: list[Result] = []
        try:
            for line in open(f"{workdir}/ports.json"):
                d = json.loads(line)
                out.append(Result(kind="open_port", target=d.get("host",""), port=d.get("port"), severity="info", raw=d))
        except Exception:
            pass
        return out
EOF

# nmap
w plugins/nmap/manifest.yaml <<'EOF'
name: nmap
category: active
phase: [2, 3]
image: instrumentisto/nmap:latest
inputs:
  - { name: target, type: string, required: true }
  - { name: ports,  type: string, default: "1-1000" }
outputs:
  - { name: open_ports, type: json, path: "/out/ports.json" }
command: >
  docker run --rm -v {{workdir}}:/out instrumentisto/nmap:latest
  -sV -sC -p {{ports}} -oX /out/scan.xml -oJ /out/ports.json {{target}}
timeout: 1800
rate_limit: { max_concurrent: 4 }
enabled: true
tags: [network, ports]
EOF

w plugins/nmap/runner.py <<'EOF'
import tempfile, subprocess, json
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, ports: str = "1-1000", **kw):
        wd = tempfile.mkdtemp(prefix="autobug_nmap_")
        cmd = f"docker run --rm -v {wd}:/out instrumentisto/nmap:latest -sV -sC -p {ports} -oX /out/scan.xml -oJ /out/ports.json {target}"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=1800)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        try:
            data = json.load(open(f"{workdir}/ports.json"))
        except Exception:
            return []
        out: list[Result] = []
        for host in data.get("hosts", []):
            addr = host.get("addr", "")
            for port in host.get("ports", []):
                out.append(Result(kind="open_port", target=addr, port=port.get("port"),
                                  service=(port.get("service") or {}).get("name"),
                                  severity="info", raw=port))
        return out
EOF

# nuclei
w plugins/nuclei/manifest.yaml <<'EOF'
name: nuclei
category: vuln
phase: [2, 3]
image: projectdiscovery/nuclei:latest
inputs:
  - { name: target, type: string, required: true }
outputs:
  - { name: findings, type: json, path: "/out/findings.json" }
command: >
  docker run --rm -v {{workdir}}:/out projectdiscovery/nuclei:latest
  -u {{target}} -silent -jsonl -o /out/findings.json -severity critical,high,medium,low,info
timeout: 1800
rate_limit: { max_concurrent: 4 }
enabled: true
tags: [cve, exposure, takeover]
EOF

w plugins/nuclei/runner.py <<'EOF'
import tempfile, subprocess, json
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_nuclei_")
        cmd = f"docker run --rm -v {wd}:/out projectdiscovery/nuclei:latest -u {target} -silent -jsonl -o /out/findings.json -severity critical,high,medium,low,info"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=1800)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        out: list[Result] = []
        try:
            for line in open(f"{workdir}/findings.json"):
                d = json.loads(line)
                info = d.get("info", {})
                out.append(Result(kind=d.get("template-id","nuclei"),
                                  target=d.get("matched-at", d.get("host","")),
                                  severity=info.get("severity","info"), raw=d))
        except Exception:
            pass
        return out
EOF

# dalfox
w plugins/dalfox/manifest.yaml <<'EOF'
name: dalfox
category: vuln
phase: [3]
image: hahwul/dalfox:latest
inputs:
  - { name: target, type: string, required: true }
outputs:
  - { name: findings, type: json, path: "/out/findings.json" }
command: >
  docker run --rm -v {{workdir}}:/out hahwul/dalfox:latest
  url {{target}} --silence --output /out/findings.json --format json
timeout: 900
rate_limit: { max_concurrent: 4 }
enabled: true
tags: [xss]
EOF

w plugins/dalfox/runner.py <<'EOF'
import tempfile, subprocess, json
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_dalfox_")
        cmd = f"docker run --rm -v {wd}:/out hahwul/dalfox:latest url {target} --silence --output /out/findings.json --format json"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=900)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        out: list[Result] = []
        try:
            data = json.load(open(f"{workdir}/findings.json"))
            items = data if isinstance(data, list) else data.get("findings", [])
            for d in items:
                out.append(Result(kind="xss", target=d.get("data", d.get("url","")), severity="high", raw=d))
        except Exception:
            pass
        return out
EOF

# sqlmap
w plugins/sqlmap/manifest.yaml <<'EOF'
name: sqlmap
category: vuln
phase: [3]
image: googlesecurity/sqlmap:latest
inputs:
  - { name: target, type: string, required: true }
outputs:
  - { name: result, type: text, path: "/out/result.txt" }
command: >
  docker run --rm -v {{workdir}}:/out googlesecurity/sqlmap:latest
  -u "{{target}}" --batch --level=2 --risk=2 --output-dir=/out --flush-session
timeout: 1800
rate_limit: { max_concurrent: 2 }
enabled: true
tags: [sqli]
EOF

w plugins/sqlmap/runner.py <<'EOF'
import tempfile, subprocess, glob
from plugins.runner_base import PluginBase
from plugins._schema import Result

class Plugin(PluginBase):
    def run(self, target: str, **kw):
        wd = tempfile.mkdtemp(prefix="autobug_sqlmap_")
        cmd = f'docker run --rm -v {wd}:/out googlesecurity/sqlmap:latest -u "{target}" --batch --level=2 --risk=2 --output-dir=/out --flush-session'
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=1800)
        return wd, out.stdout, out.stderr
    def parse(self, workdir: str) -> list[Result]:
        out: list[Result] = []
        for log in glob.glob(f"{workdir}/**/log", recursive=True):
            try:
                txt = open(log, errors="ignore").read()
            except Exception:
                continue
            if "is vulnerable" in txt or "Parameter:" in txt:
                out.append(Result(kind="sqli", target=workdir, severity="high", raw={"log": log}))
        return out
EOF

# ---------- osint ----------
w osint/__init__.py <<'EOF'
EOF

w osint/service.py <<'EOF'
from osint.sources import email as s_email, domain as s_domain, phone as s_phone, image as s_image

HANDLERS = {"email": s_email.run, "domain": s_domain.run, "phone": s_phone.run, "image": s_image.run}

def run(input_type: str, value: str) -> dict:
    fn = HANDLERS.get(input_type)
    if not fn:
        return {"error": f"unknown type {input_type}", "sources": []}
    return fn(value)

def run_domain_osint(domain: str) -> dict:
    return s_domain.run(domain)
EOF

w osint/profile_builder.py <<'EOF'
def build(input_type: str, value: str, results: dict) -> dict:
    return {"input_type": input_type, "input_value": value,
            "sources": results.get("sources", []),
            "raw": results}
EOF

w osint/sources/__init__.py <<'EOF'
EOF

w osint/sources/email.py <<'EOF'
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
EOF

w osint/sources/domain.py <<'EOF'
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
EOF

w osint/sources/phone.py <<'EOF'
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
EOF

w osint/sources/image.py <<'EOF'
import subprocess, tempfile, os, httpx, json

def run(url_or_path: str) -> dict:
    out = {"input": url_or_path, "type": "image", "sources": [], "data": {}}
    tmp = None
    try:
        if url_or_path.startswith("http"):
            tmp = tempfile.NamedTemporaryFile(suffix=".img", delete=False).name
            r = httpx.get(url_or_path, timeout=20)
            open(tmp, "wb").write(r.content)
        else:
            tmp = url_or_path
        try:
            meta = subprocess.run(["exiftool", "-json", tmp], capture_output=True, text=True, timeout=20)
            if meta.returncode == 0:
                out["data"]["exif"] = json.loads(meta.stdout)
                out["sources"].append("exiftool")
        except Exception:
            pass
        try:
            ocr = subprocess.run(["tesseract", tmp, "stdout"], capture_output=True, text=True, timeout=30)
            if ocr.returncode == 0 and ocr.stdout.strip():
                out["data"]["ocr_text"] = ocr.stdout.strip()
                out["sources"].append("tesseract")
        except Exception:
            pass
    finally:
        if tmp and tmp.startswith(tempfile.gettempdir()) and os.path.exists(tmp):
            os.unlink(tmp)
    return out
EOF

# ---------- reports ----------
w reports/__init__.py <<'EOF'
EOF

w reports/render.py <<'EOF'
import os
from jinja2 import Environment, FileSystemLoader
from api.storage import put_object

HERE = os.path.dirname(__file__)
env = Environment(loader=FileSystemLoader(os.path.join(HERE, "templates")))

def render_report(scan, findings) -> str:
    template = env.get_template("report.html.j2")
    html = template.render(scan=scan, findings=findings, counts=_counts(findings))
    out_dir = os.path.join(os.getenv("DATA_DIR", "/app/data"), "reports")
    os.makedirs(out_dir, exist_ok=True)
    html_path = os.path.join(out_dir, f"scan_{scan.id}.html")
    with open(html_path, "w") as f:
        f.write(html)
    pdf_path = os.path.join(out_dir, f"scan_{scan.id}.pdf")
    try:
        from weasyprint import HTML
        HTML(string=html).write_pdf(pdf_path)
    except Exception:
        pdf_path = html_path
    for p in [html_path, pdf_path]:
        if os.path.exists(p):
            try:
                put_object(f"scans/{scan.id}/report/{os.path.basename(p)}", p)
            except Exception:
                pass
    return pdf_path

def _counts(findings):
    c: dict[str, int] = {}
    for f in findings:
        c[f.severity] = c.get(f.severity, 0) + 1
    return c
EOF

w reports/templates/report.html.j2 <<'EOF'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
  body { font-family: -apple-system, system-ui, sans-serif; color: #111; margin: 40px; }
  h1 { font-size: 24px; margin-bottom: 8px; }
  .meta { color: #666; font-size: 13px; margin-bottom: 32px; }
  .counts { display: flex; gap: 16px; margin-bottom: 32px; }
  .counts div { padding: 8px 14px; border-radius: 8px; background: #f4f4f5; font-size: 13px; }
  .finding { page-break-inside: avoid; border-top: 1px solid #e4e4e7; padding-top: 16px; margin-top: 16px; }
  .sev { text-transform: uppercase; font-size: 11px; letter-spacing: 0.1em; }
  .critical { color: #b91c1c; } .high { color: #c2410c; } .medium { color: #a16207; }
  .low { color: #4d7c0f; } .info { color: #3b82f6; }
  pre { background: #f4f4f5; padding: 12px; border-radius: 6px; font-size: 11px; overflow-x: auto; }
</style>
</head>
<body>
  <h1>AutoBug Report — {{ scan.target }}</h1>
  <div class="meta">
    scan #{{ scan.id }} · mode {{ scan.mode }} · status {{ scan.status }}<br>
    started {{ scan.started }} · ended {{ scan.ended or "—" }}
  </div>
  <div class="counts">
    {% for sev, n in counts.items() %}
      <div class="{{ sev }}">{{ sev }}: {{ n }}</div>
    {% endfor %}
  </div>
  {% for f in findings %}
  <div class="finding">
    <div class="sev {{ f.severity }}">{{ f.severity }}</div>
    <h2>{{ f.title }}</h2>
    <div style="color:#666;font-size:13px">{{ f.url }}</div>
    <p>{{ f.desc }}</p>
  </div>
  {% endfor %}
</body>
</html>
EOF

# ---------- telegram ----------
w telegram/__init__.py <<'EOF'
EOF

w telegram/bot.py <<'EOF'
import asyncio, json
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes
from api.redis_client import r
from api.settings import settings

_APP = None

async def start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    chat = update.effective_chat.id
    await update.message.reply_text(f"AutoBug linked. chat_id={chat}\nAdd it to TELEGRAM_ALLOWED_CHATS in .env and restart.")

async def _send(chat_id, text):
    if _APP:
        try: await _APP.bot.send_message(chat_id=chat_id, text=text)
        except Exception: pass

async def watch():
    pubsub = r.pubsub()
    pubsub.psubscribe("scan:*")
    while True:
        msg = pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
        if msg and msg.get("type") == "pmessage":
            try:
                evt = json.loads(msg["data"])
            except Exception:
                await asyncio.sleep(0.1); continue
            if evt.get("level") not in ("done", "warn"): 
                await asyncio.sleep(0.05); continue
            node = evt.get("node", "")
            if not any(k in node for k in ("vuln", "nuclei", "dalfox", "notify", "report")):
                await asyncio.sleep(0.05); continue
            text = f"{node}\nscan: {evt.get('scan_id')}\n{evt.get('payload')}"
            for chat in settings.chats:
                await _send(chat, text)
        await asyncio.sleep(0.05)

async def main():
    global _APP
    if not settings.TELEGRAM_BOT_TOKEN:
        print("no TELEGRAM_BOT_TOKEN, idling")
        while True: await asyncio.sleep(60)
    _APP = Application.builder().token(settings.TELEGRAM_BOT_TOKEN).build()
    _APP.add_handler(CommandHandler("start", start))
    await _APP.initialize()
    await _APP.start()
    await _APP.updater.start_polling()
    await watch()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# ---------- ui ----------
w ui/Dockerfile <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
EOF

w ui/package.json <<'EOF'
{
  "name": "autobug-ui",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.26.2",
    "framer-motion": "^11.11.9",
    "recharts": "^2.13.0",
    "lucide-react": "^0.453.0",
    "clsx": "^2.1.1"
  },
  "devDependencies": {
    "@types/react": "^18.3.11",
    "@types/react-dom": "^18.3.1",
    "@vitejs/plugin-react": "^4.3.2",
    "typescript": "^5.6.3",
    "vite": "^5.4.9",
    "tailwindcss": "^3.4.13",
    "postcss": "^8.4.47",
    "autoprefixer": "^10.4.20"
  }
}
EOF

w ui/vite.config.ts <<'EOF'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({ plugins: [react()], server: { port: 5173, host: true } });
EOF

w ui/index.html <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>AutoBug</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

w ui/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true,
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true
  },
  "include": ["src"]
}
EOF

w ui/tailwind.config.js <<'EOF'
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#0A0A0B",
        fg: "#EDEDEF",
        accent: "#3B82F6",
        sev: { crit: "#B91C1C", high: "#C2410C", med: "#A16207", low: "#4D7C0F", info: "#3B82F6" },
      },
    },
  },
  plugins: [],
};
EOF

w ui/postcss.config.js <<'EOF'
export default { plugins: { tailwindcss: {}, autoprefixer: {} } };
EOF

w ui/src/index.css <<'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
:root { --bg: #0A0A0B; --fg: #EDEDEF; --accent: #3B82F6; }
html, body, #root { height: 100%; }
body { background: var(--bg); color: var(--fg); font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", Inter, system-ui, sans-serif; -webkit-font-smoothing: antialiased; }
EOF

w ui/src/main.tsx <<'EOF'
import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import "./index.css";
import Dashboard from "./pages/Dashboard";
import ScanDetail from "./pages/ScanDetail";
import Osint from "./pages/Osint";
import Plugins from "./pages/Plugins";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/scans/:id" element={<ScanDetail />} />
        <Route path="/osint" element={<Osint />} />
        <Route path="/plugins" element={<Plugins />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>
);
EOF

w ui/src/lib/api.ts <<'EOF'
const API = (import.meta as any).env?.VITE_API || "http://localhost:8000";
export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const r = await fetch(`${API}${path}`, { ...init, headers: { "Content-Type": "application/json", ...(init?.headers || {}) } });
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}
export const getScans = () => api<any[]>("/api/scans");
export const getScan = (id: string | number) => api<any>(`/api/scans/${id}`);
export const createScan = (body: any) => api<any>("/api/scans", { method: "POST", body: JSON.stringify(body) });
export const getFindings = (id: string | number) => api<any[]>(`/api/findings?scan_id=${id}`);
export const getPlugins = () => api<any[]>("/api/plugins");
export const runOsint = (body: any) => api<any>("/api/osint/run", { method: "POST", body: JSON.stringify(body) });
EOF

w ui/src/lib/ws.ts <<'EOF'
export function connectScanWS(scanId: number | string, onEvent: (e: any) => void): () => void {
  const API = (import.meta as any).env?.VITE_API || "http://localhost:8000";
  const wsUrl = API.replace(/^http/, "ws") + `/ws/scans/${scanId}`;
  let ws: WebSocket | null = null;
  let closed = false;
  let backoff = 500;
  const open = () => {
    if (closed) return;
    ws = new WebSocket(wsUrl);
    ws.onmessage = (m) => { try { onEvent(JSON.parse(m.data)); } catch {} };
    ws.onopen = () => { backoff = 500; };
    ws.onclose = () => { if (closed) return; setTimeout(open, backoff); backoff = Math.min(backoff * 2, 8000); };
  };
  open();
  return () => { closed = true; ws?.close(); };
}
EOF

w ui/src/components/DagView.tsx <<'EOF'
import { motion } from "framer-motion";
const NODES = ["scope_validate","target_intake","passive_recon","asset_dedup","asset_graph","active_recon","live_hosts","tech_fingerprint","osint_recon","vuln_scan","finding_dedup","severity_triage","exploit_verify","screenshot","report_generate","notify"];
export default function DagView({ status }: { status: Record<string, string> }) {
  return (
    <div className="flex flex-col gap-3 p-6">
      {NODES.map((n, i) => {
        const s = status[n] || "pending";
        const color = s === "done" ? "#22c55e" : s === "active" ? "#3B82F6" : s === "fail" ? "#B91C1C" : "#3f3f46";
        return (
          <motion.div key={n} initial={{ opacity: 0, x: -12 }} animate={{ opacity: 1, x: 0 }}
            transition={{ delay: i * 0.02, type: "spring", stiffness: 300, damping: 24 }}
            className="flex items-center gap-3">
            <motion.span animate={{ scale: s === "active" ? [1, 1.25, 1] : 1 }}
              transition={{ repeat: s === "active" ? Infinity : 0, duration: 1.2 }}
              className="w-3 h-3 rounded-full" style={{ background: color }} />
            <span className="text-sm text-fg/80">{n}</span>
            <span className="ml-auto text-xs text-fg/40">{s}</span>
          </motion.div>
        );
      })}
    </div>
  );
}
EOF

w ui/src/components/FindingCard.tsx <<'EOF'
import { motion } from "framer-motion";
const SEV: Record<string, string> = {
  critical: "text-sev-crit border-sev-crit",
  high: "text-sev-high border-sev-high",
  medium: "text-sev-med border-sev-med",
  low: "text-sev-low border-sev-low",
  info: "text-sev-info border-sev-info",
};
export default function FindingCard({ f }: { f: any }) {
  const c = SEV[f.severity] || SEV.info;
  return (
    <motion.div initial={{ opacity: 0, x: 20, filter: "blur(4px)" }} animate={{ opacity: 1, x: 0, filter: "blur(0px)" }}
      transition={{ duration: 0.25, ease: "easeOut" }}
      className={`rounded-xl border bg-white/[0.02] p-4 ${c.split(" ")[1]}`}>
      <div className="flex items-center justify-between">
        <span className={`text-xs uppercase tracking-wider ${c.split(" ")[0]}`}>{f.severity}</span>
        <span className="text-xs text-fg/40">{f.tool}</span>
      </div>
      <div className="mt-2 text-sm text-fg/90">{f.title}</div>
      <div className="mt-1 text-xs text-fg/50 truncate">{f.url}</div>
    </motion.div>
  );
}
EOF

w ui/src/components/SeverityRing.tsx <<'EOF'
import { motion } from "framer-motion";
export default function SeverityRing({ counts }: { counts: Record<string, number> }) {
  const total = Object.values(counts).reduce((a, b) => a + b, 0) || 1;
  const order = ["critical","high","medium","low","info"];
  const colors = ["#B91C1C","#C2410C","#A16207","#4D7C0F","#3B82F6"];
  let offset = 0;
  const r = 42, c = 2 * Math.PI * r;
  return (
    <svg viewBox="0 0 100 100" className="w-32 h-32 -rotate-90">
      {order.map((s, i) => {
        const v = counts[s] || 0;
        const len = (v / total) * c;
        const el = (
          <motion.circle key={s} cx="50" cy="50" r={r} fill="none" stroke={colors[i]} strokeWidth="8"
            strokeDasharray={`${len} ${c}`} strokeDashoffset={-offset}
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.5, delay: i * 0.05 }} />
        );
        offset += len;
        return el;
      })}
    </svg>
  );
}
EOF

w ui/src/pages/Dashboard.tsx <<'EOF'
import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { Link, useNavigate } from "react-router-dom";
import { getScans, createScan } from "../lib/api";

export default function Dashboard() {
  const [scans, setScans] = useState<any[]>([]);
  const [target, setTarget] = useState("");
  const [mode, setMode] = useState(3);
  const [ack, setAck] = useState(false);
  const [busy, setBusy] = useState(false);
  const nav = useNavigate();

  const load = async () => { try { setScans(await getScans()); } catch {} };
  useEffect(() => { load(); const t = setInterval(load, 5000); return () => clearInterval(t); }, []);

  const launch = async () => {
    if (!target || !ack) return;
    setBusy(true);
    try { const s = await createScan({ target, mode, scope_ack: true }); nav(`/scans/${s.id}`); }
    finally { setBusy(false); }
  };

  return (
    <div className="min-h-screen flex">
      <aside className="w-72 border-r border-white/5 p-5 flex flex-col gap-4">
        <div className="text-lg font-medium tracking-tight">AutoBug</div>
        <div className="flex flex-col gap-2">
          <input value={target} onChange={(e) => setTarget(e.target.value)} placeholder="target.com"
            className="bg-white/5 rounded-lg px-3 py-2 text-sm outline-none border border-white/5 focus:border-accent/60" />
          <div className="flex gap-1">
            {[1,2,3].map((m) => (
              <button key={m} onClick={() => setMode(m)}
                className={`flex-1 text-xs py-2 rounded-lg border transition ${mode === m ? "border-accent text-accent bg-accent/10" : "border-white/5 text-fg/60"}`}>
                mode {m}
              </button>
            ))}
          </div>
          <label className="flex items-center gap-2 text-xs text-fg/60">
            <input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} />
            I own or am authorized to test this target
          </label>
          <button disabled={!target || !ack || busy} onClick={launch}
            className="bg-accent text-white text-sm rounded-lg py-2 disabled:opacity-40">
            {busy ? "launching…" : "launch scan"}
          </button>
        </div>
        <Link to="/osint" className="text-xs text-fg/60 hover:text-fg">→ OSINT</Link>
        <Link to="/plugins" className="text-xs text-fg/60 hover:text-fg">→ Plugins</Link>
      </aside>
      <main className="flex-1 p-8">
        <h1 className="text-2xl font-medium mb-6">Scans</h1>
        <div className="flex flex-col gap-3">
          {scans.map((s) => (
            <motion.div key={s.id} layout initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}>
              <Link to={`/scans/${s.id}`} className="block rounded-xl border border-white/5 bg-white/[0.02] p-4 hover:border-white/10">
                <div className="flex items-center justify-between">
                  <div className="text-sm">{s.target}</div>
                  <div className="text-xs text-fg/40">mode {s.mode} · {s.status}</div>
                </div>
              </Link>
            </motion.div>
          ))}
          {scans.length === 0 && <div className="text-fg/40 text-sm">no scans yet</div>}
        </div>
      </main>
    </div>
  );
}
EOF

w ui/src/pages/ScanDetail.tsx <<'EOF'
import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { getScan, getFindings } from "../lib/api";
import { connectScanWS } from "../lib/ws";
import DagView from "../components/DagView";
import FindingCard from "../components/FindingCard";
import SeverityRing from "../components/SeverityRing";

export default function ScanDetail() {
  const { id } = useParams();
  const [scan, setScan] = useState<any>(null);
  const [findings, setFindings] = useState<any[]>([]);
  const [status, setStatus] = useState<Record<string, string>>({});

  useEffect(() => {
    if (!id) return;
    getScan(id).then(setScan).catch(() => {});
    getFindings(id).then(setFindings).catch(() => {});
    const close = connectScanWS(id, (e) => {
      setStatus((s) => ({ ...s, [e.node]: e.level === "done" ? "done" : e.level === "warn" ? "fail" : "active" }));
      if (e.node === "vuln_scan" || e.node === "finding_dedup") getFindings(id).then(setFindings).catch(() => {});
    });
    const t = setInterval(() => getFindings(id).then(setFindings).catch(() => {}), 4000);
    return () => { close(); clearInterval(t); };
  }, [id]);

  const counts = findings.reduce((a: any, f) => { a[f.severity] = (a[f.severity] || 0) + 1; return a; }, {});

  return (
    <div className="min-h-screen flex">
      <div className="w-80 border-r border-white/5 p-5">
        <div className="text-sm text-fg/60 mb-4">{scan?.target}</div>
        <DagView status={status} />
      </div>
      <main className="flex-1 p-8">
        <div className="flex items-center gap-8 mb-8">
          <SeverityRing counts={counts} />
          <div className="grid grid-cols-5 gap-4">
            {["critical","high","medium","low","info"].map((s) => (
              <div key={s} className="text-center">
                <div className="text-2xl">{counts[s] || 0}</div>
                <div className="text-xs text-fg/40 uppercase">{s}</div>
              </div>
            ))}
          </div>
        </div>
        <div className="flex flex-col gap-3">
          {findings.map((f) => <FindingCard key={f.id} f={f} />)}
        </div>
      </main>
    </div>
  );
}
EOF

w ui/src/pages/Osint.tsx <<'EOF'
import { useState } from "react";
import { motion } from "framer-motion";
import { runOsint } from "../lib/api";
const TYPES = ["email", "domain", "phone", "image"] as const;

export default function Osint() {
  const [type, setType] = useState<typeof TYPES[number]>("email");
  const [value, setValue] = useState("");
  const [result, setResult] = useState<any>(null);
  const [busy, setBusy] = useState(false);

  const run = async () => {
    setBusy(true); setResult(null);
    try { setResult(await runOsint({ type, value })); } finally { setBusy(false); }
  };

  return (
    <div className="min-h-screen p-8 max-w-3xl mx-auto">
      <h1 className="text-2xl mb-6">OSINT</h1>
      <div className="flex gap-2 mb-4">
        {TYPES.map((t) => (
          <button key={t} onClick={() => setType(t)}
            className={`px-3 py-1.5 text-xs rounded-lg border ${type === t ? "border-accent text-accent bg-accent/10" : "border-white/5 text-fg/60"}`}>
            {t}
          </button>
        ))}
      </div>
      <div className="flex gap-2">
        <input value={value} onChange={(e) => setValue(e.target.value)}
          placeholder={type === "email" ? "user@example.com" : type === "domain" ? "example.com" : type === "phone" ? "+91..." : "image URL"}
          className="flex-1 bg-white/5 rounded-lg px-3 py-2 text-sm outline-none border border-white/5 focus:border-accent/60" />
        <button onClick={run} disabled={!value || busy} className="bg-accent text-white text-sm rounded-lg px-4 disabled:opacity-40">
          {busy ? "…" : "run"}
        </button>
      </div>
      {result && (
        <motion.pre initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
          className="mt-6 text-xs bg-white/[0.02] border border-white/5 rounded-xl p-4 overflow-auto">
          {JSON.stringify(result, null, 2)}
        </motion.pre>
      )}
    </div>
  );
}
EOF

w ui/src/pages/Plugins.tsx <<'EOF'
import { useEffect, useState } from "react";
import { getPlugins } from "../lib/api";

export default function Plugins() {
  const [plugins, setPlugins] = useState<any[]>([]);
  useEffect(() => { getPlugins().then(setPlugins).catch(() => {}); }, []);
  return (
    <div className="min-h-screen p-8 max-w-5xl mx-auto">
      <h1 className="text-2xl mb-6">Plugins</h1>
      <div className="grid grid-cols-2 gap-3">
        {plugins.map((p) => (
          <div key={p.name} className="rounded-xl border border-white/5 bg-white/[0.02] p-4">
            <div className="flex items-center justify-between">
              <span className="text-sm">{p.name}</span>
              <span className="text-xs text-fg/40">{p.category}</span>
            </div>
            <div className="text-xs text-fg/50 mt-1">phase {p.phase.join(", ")}</div>
            <div className="flex gap-1 mt-2">
              {p.tags.map((t: string) => (
                <span key={t} className="text-[10px] px-1.5 py-0.5 rounded bg-white/5 text-fg/60">{t}</span>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
EOF

# ---------- data ----------
mkdir -p data
cat > data/scope.json <<'EOF'
{ "allowed": ["scanme.nmap.org", "example.com"] }
EOF

echo "AutoBug tree written to $ROOT"
echo "Files: $(find . -type f | wc -l)"
