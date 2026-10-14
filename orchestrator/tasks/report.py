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
