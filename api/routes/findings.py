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
