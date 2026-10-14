from pydantic import BaseModel, Field
from typing import Any, Literal

Category = Literal["recon", "active", "vuln", "exploit", "osint", "screenshot", "report"]

class InputSpec(BaseModel):
    name: str
    type: str = "string"
    required: bool = False
    default: Any = None

class OutputSpec(BaseModel):
    name: str
    type: str = "json"
    path: str

class RateLimit(BaseModel):
    max_concurrent: int = 4

class Manifest(BaseModel):
    name: str
    category: Category
    phase: list[int] = Field(default_factory=list)
    image: str
    inputs: list[InputSpec] = Field(default_factory=list)
    outputs: list[OutputSpec] = Field(default_factory=list)
    command: str
    timeout: int = 1800
    rate_limit: RateLimit = RateLimit()
    enabled: bool = True
    tags: list[str] = Field(default_factory=list)

class Result(BaseModel):
    kind: str
    target: str
    port: int | None = None
    service: str | None = None
    severity: Literal["info", "low", "medium", "high", "critical"] = "info"
    raw: dict | None = None
    evidence_ref: str | None = None
