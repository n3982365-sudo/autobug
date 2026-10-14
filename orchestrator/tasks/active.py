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
