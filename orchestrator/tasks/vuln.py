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
