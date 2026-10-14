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
