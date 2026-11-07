"""MCS4302 Week 7 lab: offline-first sync endpoints (under /w7).

Add to your main.py:
    from week7 import router as week7_router
    app.include_router(week7_router)
Or run alone:
    uvicorn week7:app --host 0.0.0.0 --port 8000

State is kept in memory. POST /w7/reset starts every run from the same state:
task-42 = "Pump repair", status open, version 3, plus 499 filler tasks,
and the change-log cursor at 120 (as on lecture slide 22).
"""
from __future__ import annotations

import threading
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Literal, Optional

from fastapi import APIRouter, FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from fastapi.routing import APIRoute
from pydantic import BaseModel


# ---------------------------------------------------------------- byte counting
_STATS: Dict[str, Dict[str, int]] = {}


class CountingRoute(APIRoute):
    """Counts request and response BODY bytes per route (headers excluded)."""

    def get_route_handler(self) -> Callable:
        original = super().get_route_handler()
        path = self.path

        async def handler(request: Request) -> Response:
            body = await request.body()
            response = await original(request)
            s = _STATS.setdefault(path, {"calls": 0, "req_bytes": 0,
                                         "resp_bytes": 0, "last_resp_bytes": 0})
            s["calls"] += 1
            s["req_bytes"] += len(body)
            n = len(getattr(response, "body", b"") or b"")
            s["resp_bytes"] += n
            s["last_resp_bytes"] = n
            return response

        return handler


router = APIRouter(prefix="/w7", tags=["week7"], route_class=CountingRoute)

# ---------------------------------------------------------------- server state
_lock = threading.Lock()
FIELDS = ("title", "status")
START_CURSOR = 120

_state: Dict[str, Any] = {}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(t: datetime) -> str:
    return t.isoformat(timespec="milliseconds")


def _parse(ts: str) -> datetime:
    t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def _seed(mode: str) -> None:
    base = _iso(_now() - timedelta(hours=1))
    tasks: Dict[str, Dict[str, Any]] = {
        "task-42": {"id": "task-42", "title": "Pump repair", "status": "open",
                    "version": 3, "updated_at": base, "is_deleted": False}
    }
    for i in range(1, 500):
        tid = f"task-{i + 1000}"
        tasks[tid] = {"id": tid, "title": f"Routine check {i}", "status": "open",
                      "version": 1, "updated_at": base, "is_deleted": False}
    _state.clear()
    _state.update({
        "mode": mode,
        "tasks": tasks,
        "log": [],                 # list of (seq, task_id)
        "seq": START_CURSOR,
        "idem": {},                # idem_key -> stored response body
        "drop_next_reply": False,
    })
    _STATS.clear()


def _log_change(task_id: str) -> None:
    _state["seq"] += 1
    _state["log"].append((_state["seq"], task_id))


_seed("version")


# ---------------------------------------------------------------- models
class ResetIn(BaseModel):
    mode: Literal["lww", "version"] = "version"


class SyncOp(BaseModel):
    idem_key: str
    op: Literal["update", "delete"]
    task_id: str
    # version mode: the version the edit was based on + only the changed fields
    base_version: Optional[int] = None
    fields: Dict[str, Any] = {}
    # lww mode: the whole record + the device timestamp of the edit
    record: Optional[Dict[str, Any]] = None
    updated_at: Optional[str] = None


class PhoneBEdit(BaseModel):
    task_id: str = "task-42"
    field: Literal["title", "status"]
    value: str
    clock_skew_min: int = 10


# ---------------------------------------------------------------- control endpoints
@router.post("/reset")
def reset(body: ResetIn):
    with _lock:
        _seed(body.mode)
        return {"mode": body.mode, "cursor": _state["seq"], "tasks": len(_state["tasks"])}


@router.get("/mode")
def get_mode():
    return {"mode": _state["mode"]}


@router.post("/fault/drop-next-reply")
def drop_next_reply():
    _state["drop_next_reply"] = True
    return {"drop_next_reply": True}


@router.get("/stats")
def stats():
    # Snapshot taken before this call is counted.
    return {"mode": _state["mode"], "endpoints": {k: dict(v) for k, v in _STATS.items()}}


@router.post("/phone-b/edit")
def phone_b_edit(body: PhoneBEdit):
    """Phone B edits online. Its clock is clock_skew_min minutes fast."""
    with _lock:
        t = _state["tasks"].get(body.task_id)
        if t is None:
            raise HTTPException(404, "no such task")
        t[body.field] = body.value
        t["version"] += 1
        t["updated_at"] = _iso(_now() + timedelta(minutes=body.clock_skew_min))
        _log_change(body.task_id)
        return {"task": dict(t)}


# ---------------------------------------------------------------- data endpoints
@router.get("/tasks")
def all_tasks():
    """Full re-download of the dataset, plus the current cursor."""
    with _lock:
        return {"tasks": list(_state["tasks"].values()), "cursor": _state["seq"]}


@router.get("/tasks/{task_id}")
def one_task(task_id: str):
    t = _state["tasks"].get(task_id)
    if t is None:
        raise HTTPException(404, "no such task")
    return {"task": t}


@router.get("/changes")
def changes(since: int):
    """Delta sync: every task changed after `since`, oldest first, plus the new cursor."""
    with _lock:
        out: List[Dict[str, Any]] = []
        for seq, tid in _state["log"]:
            if seq > since:
                out.append({"seq": seq, "task": dict(_state["tasks"][tid])})
        return {"changes": out, "cursor": _state["seq"]}


@router.post("/sync")
def sync(op: SyncOp):
    """Apply ONE outbox operation. 200 {task, applied} or 409 {task: current}."""
    with _lock:
        # Idempotency: a key we have seen gets the stored reply, nothing is reapplied.
        if op.idem_key in _state["idem"]:
            return _state["idem"][op.idem_key]

        t = _state["tasks"].get(op.task_id)
        if t is None:
            raise HTTPException(404, "no such task")

        if _state["mode"] == "version":
            if op.base_version is None:
                raise HTTPException(400, "version mode needs base_version")
            if op.base_version != t["version"]:
                # Not stored under the key: after a merge the client resends with a NEW key.
                return JSONResponse(status_code=409, content={"task": dict(t)})
            if op.op == "delete":
                t["is_deleted"] = True
            else:
                for k, v in op.fields.items():
                    if k in FIELDS:
                        t[k] = v
            t["version"] += 1
            t["updated_at"] = _iso(_now())
            _log_change(t["id"])
            applied = True
        else:  # lww: newest device timestamp wins, the whole record is replaced
            if not op.updated_at:
                raise HTTPException(400, "lww mode needs updated_at")
            applied = _parse(op.updated_at) > _parse(t["updated_at"])
            if applied:
                if op.op == "delete":
                    t["is_deleted"] = True
                else:
                    for k in FIELDS:
                        if op.record and k in op.record:
                            t[k] = op.record[k]
                t["version"] += 1
                t["updated_at"] = op.updated_at
                _log_change(t["id"])
            # applied == False: the edit is dropped silently (that is LWW)

        reply = {"task": dict(t), "applied": applied}
        _state["idem"][op.idem_key] = reply

        if _state["drop_next_reply"]:
            # The change IS applied, but the phone never hears about it.
            _state["drop_next_reply"] = False
            return JSONResponse(status_code=500, content={"detail": "reply lost (injected)"})
        return reply


# Run this file on its own: uvicorn week7:app --host 0.0.0.0 --port 8000
app = FastAPI(title="MCS4302 Week 7")
app.include_router(router)
