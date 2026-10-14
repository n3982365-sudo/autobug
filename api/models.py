from sqlalchemy.orm import declarative_base, Mapped, mapped_column
from sqlalchemy import Integer, String, DateTime, Boolean, ForeignKey, Text, JSON, Float
from datetime import datetime

Base = declarative_base()

class Scan(Base):
    __tablename__ = "scans"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    target: Mapped[str] = mapped_column(String)
    mode: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String, default="queued")
    started: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    ended: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    operator: Mapped[str | None] = mapped_column(String, nullable=True)
    scope_ack: Mapped[bool] = mapped_column(Boolean, default=False)
    allow_exploit: Mapped[bool] = mapped_column(Boolean, default=False)

class Asset(Base):
    __tablename__ = "assets"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    scan_id: Mapped[int] = mapped_column(ForeignKey("scans.id"))
    host: Mapped[str] = mapped_column(String)
    ip: Mapped[str | None] = mapped_column(String, nullable=True)
    status: Mapped[str | None] = mapped_column(String, nullable=True)
    tech: Mapped[list | None] = mapped_column(JSON, nullable=True)
    ports: Mapped[list | None] = mapped_column(JSON, nullable=True)
    tls: Mapped[dict | None] = mapped_column(JSON, nullable=True)

class Finding(Base):
    __tablename__ = "findings"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    scan_id: Mapped[int] = mapped_column(ForeignKey("scans.id"))
    asset_id: Mapped[int | None] = mapped_column(ForeignKey("assets.id"), nullable=True)
    kind: Mapped[str] = mapped_column(String)
    severity: Mapped[str] = mapped_column(String, default="info")
    cvss: Mapped[float | None] = mapped_column(Float, nullable=True)
    title: Mapped[str] = mapped_column(String)
    desc: Mapped[str | None] = mapped_column(Text, nullable=True)
    repro: Mapped[str | None] = mapped_column(Text, nullable=True)
    evidence_ref: Mapped[str | None] = mapped_column(String, nullable=True)
    tool: Mapped[str | None] = mapped_column(String, nullable=True)
    url: Mapped[str | None] = mapped_column(String, nullable=True)
    dedup_hash: Mapped[str] = mapped_column(String, index=True)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)

class Event(Base):
    __tablename__ = "events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    scan_id: Mapped[int] = mapped_column(ForeignKey("scans.id"))
    ts: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    node: Mapped[str] = mapped_column(String)
    level: Mapped[str] = mapped_column(String)
    payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)

class OsintProfile(Base):
    __tablename__ = "osint_profiles"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    input_type: Mapped[str] = mapped_column(String)
    input_value: Mapped[str] = mapped_column(String)
    result_json: Mapped[dict] = mapped_column(JSON)
    sources: Mapped[list | None] = mapped_column(JSON, nullable=True)
    ts: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
