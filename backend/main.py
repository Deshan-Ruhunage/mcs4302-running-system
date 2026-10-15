"""MCS4302 Week 4 lab backend: items API + fault-injection endpoints.

Run:  uvicorn main:app --host 0.0.0.0 --port 8000 --reload
Docs: http://localhost:8000/docs
"""
import asyncio
import random
from typing import Optional

from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field, field_validator

app = FastAPI(title="MCS4302 Week 4 backend")


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
    seed_items()
    return {"status": "reset", "seed": seed}
