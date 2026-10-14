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
