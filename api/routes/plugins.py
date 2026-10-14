from fastapi import APIRouter
from plugins.registry import registry

router = APIRouter()

@router.get("")
def list_plugins():
    return [{"name": p.name, "category": p.category, "phase": p.phase,
             "image": p.image, "enabled": p.enabled, "tags": p.tags}
            for p in registry.all()]
