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
