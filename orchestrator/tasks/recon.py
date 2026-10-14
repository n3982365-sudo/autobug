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
