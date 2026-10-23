"""MCS4302 running-system backend (Week 5): items API, fault-injection endpoints
and a background-job log.

Week 5 adds /job-log. Timestamps are taken from the SERVER clock, so an
emulator whose clock drifts cannot distort the measured job delays.

Run:  uvicorn main:app --host 0.0.0.0 --port 8000 --reload
Docs: http://localhost:8000/docs
"""
import asyncio
import random
import time
from datetime import datetime
from typing import Literal, Optional

from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field, field_validator

app = FastAPI(title="MCS4302 running system backend (Week 5)")


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    price: float = Field(ge=0, allow_inf_nan=False)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Name must not be blank")
        return value


class Item(ItemIn):
    id: int


items: dict[int, Item] = {}
next_id = 1
idempotency_cache: dict[str, tuple[ItemIn, Item]] = {}
rng = random.Random(42)


def seed_items():
    global items, next_id, idempotency_cache
    items = {
        1: Item(id=1, name="Notebook", price=450.0),
        2: Item(id=2, name="Pen", price=60.0),
    }
    next_id = 3
    idempotency_cache = {}


seed_items()


async def network_jitter():
    # Simulate normal server/network delay of 20-80 ms
    await asyncio.sleep(rng.uniform(0.02, 0.08))


@app.get("/items", response_model=list[Item])
async def list_items():
    await network_jitter()
    return list(items.values())


@app.post("/items", response_model=Item, status_code=201)
async def create_item(
    item: ItemIn,
    fail_rate: float = Query(0.0, ge=0.0, le=1.0),
    idempotency_key: Optional[str] = Header(default=None),
):
    global next_id
    await network_jitter()

    # Same key seen before: return the original result, do not create again
    if idempotency_key and idempotency_key in idempotency_cache:
        original_payload, original_result = idempotency_cache[idempotency_key]
        if original_payload != item:
            raise HTTPException(status_code=409, detail="Key reused with different data")
        return original_result

    new_item = Item(id=next_id, **item.model_dump())
    items[next_id] = new_item
    next_id += 1
    if idempotency_key:
        idempotency_cache[idempotency_key] = (item, new_item)

    # Item is saved, but the response is "lost" with probability fail_rate
    if rng.random() < fail_rate:
        raise HTTPException(status_code=500, detail="Injected failure after save")
    return new_item


@app.get("/slow")
async def slow(delay: float = Query(3.0, ge=0.0, le=30.0)):
    await asyncio.sleep(delay)
    return {"status": "ok", "delay": delay}


@app.get("/flaky")
async def flaky(fail_rate: float = Query(0.3, ge=0.0, le=1.0)):
    await network_jitter()
    if rng.random() < fail_rate:
        raise HTTPException(status_code=500, detail="Injected failure")
    return {"status": "ok"}


@app.get("/bad-json")
async def bad_json():
    await network_jitter()
    return Response(content='{"id": 1, "name": "Brok', media_type="application/json")


@app.post("/reset")
async def reset(seed: int = 42):
    global rng
    rng = random.Random(seed)
    seed_items()  # the job log is NOT cleared here; use DELETE /job-log
    return {"status": "reset", "seed": seed}


# ---------------------------------------------------------------------------
# Week 5: background-job log
# ---------------------------------------------------------------------------
class JobEventIn(BaseModel):
    job_id: str = Field(min_length=1, max_length=80)
    label: str = Field(default="", max_length=40)
    event: Literal["scheduled", "started", "ran"]
    requested_delay_s: float = Field(default=0.0, ge=0.0, le=86400.0)
    detail: str = Field(default="", max_length=200)


class JobEvent(JobEventIn):
    server_time: float  # seconds since the epoch, server clock
    server_clock: str   # same instant, readable (HH:MM:SS.mmm)


job_log: list[JobEvent] = []


def _clock(t: float) -> str:
    return datetime.fromtimestamp(t).strftime("%H:%M:%S.%f")[:-3]


@app.post("/job-log", response_model=JobEvent, status_code=201)
async def add_job_event(event: JobEventIn):
    now = time.time()
    entry = JobEvent(**event.model_dump(), server_time=now, server_clock=_clock(now))
    job_log.append(entry)
    print(f"[JOB-LOG] {entry.server_clock} {entry.event:9s} {entry.job_id} {entry.detail}")
    return entry


@app.get("/job-log", response_model=list[JobEvent])
async def list_job_events():
    return job_log


@app.get("/job-log/summary")
async def job_summary():
    """One row per job, from the events the worker REPORTED (observed times).

    Events: 'scheduled' (app registered the job), 'started' (the worker began,
    before any network work), 'ran' (the worker finished its work).

    extra_delay_s = (started - scheduled) - requested_delay_s. This is the time
    beyond the requested minimum delay until the worker began: mostly the
    deferral by Android, plus worker start-up and the small cost of logging.
    work_s = ran - started: the job's own work (fetch /items, network).
    'started' but no 'ran' means the worker has not reported success yet: it may
    still be running, be waiting to retry, or have failed. Check Logcat.
    """
    jobs: dict[str, dict] = {}
    for e in job_log:
        row = jobs.setdefault(e.job_id, {
            "job_id": e.job_id, "label": e.label, "requested_delay_s": 0.0,
            "scheduled": None, "started": None, "ran": None, "runs": 0, "detail": "",
        })
        if e.label:
            row["label"] = e.label
        if e.event == "scheduled":
            row["requested_delay_s"] = e.requested_delay_s
        if e.event == "ran":
            row["runs"] += 1
            if row["ran"] is None:
                row["detail"] = e.detail
        if row[e.event] is None:  # keep the FIRST event of each kind
            row[e.event] = e.server_time

    def clock(t):
        return _clock(t) if t is not None else None

    def diff(a, b):
        return round(b - a, 1) if a is not None and b is not None else None

    now = time.time()
    result = []
    for row in sorted(jobs.values(),
                      key=lambda r: r["scheduled"] or r["started"] or r["ran"] or 0):
        s, st, r = row["scheduled"], row["started"], row["ran"]
        to_start = diff(s, st)
        if r is not None:
            status = "done"
        elif st is not None:
            status = "started, not finished"
        else:
            status = "waiting"
        result.append({
            "job_id": row["job_id"],
            "label": row["label"],
            "requested_delay_s": row["requested_delay_s"],
            "scheduled_at": clock(s),
            "started_at": clock(st),
            "ran_at": clock(r),
            "extra_delay_s": round(to_start - row["requested_delay_s"], 1)
            if to_start is not None else None,
            "work_s": diff(st, r),
            "waiting_s": round(now - s, 1) if s is not None and st is None else None,
            "status": status,
            "runs": row["runs"],
            "detail": row["detail"],
        })
    return result


@app.delete("/job-log")
async def clear_job_log():
    job_log.clear()
    return {"status": "cleared"}
