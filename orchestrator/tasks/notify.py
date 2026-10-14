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
