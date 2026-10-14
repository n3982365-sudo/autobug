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
