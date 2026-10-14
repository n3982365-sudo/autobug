from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from osint.service import run
from api.db import SessionLocal
from api.models import OsintProfile

router = APIRouter()

class OsintReq(BaseModel):
    type: str
    value: str

@router.post("/run")
def run_osint(req: OsintReq):
    if req.type not in ("email", "domain", "phone", "image"):
        raise HTTPException(400, "unknown type")
    result = run(req.type, req.value)
    db = SessionLocal()
    db.add(OsintProfile(input_type=req.type, input_value=req.value,
                        result_json=result, sources=result.get("sources", [])))
    db.commit(); db.close()
    return result
