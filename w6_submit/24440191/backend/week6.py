"""MCS4302 Week 6 lab endpoints.

Add to your existing backend (backend/main.py):

    from week6 import router as week6_router
    app.include_router(week6_router)

Or run standalone (only the Week 6 endpoints):

    uvicorn week6:app --host 0.0.0.0 --port 8000
"""
import asyncio
import json
import random
from functools import lru_cache

from fastapi import APIRouter, FastAPI, HTTPException, Query, Response

router = APIRouter(prefix="/w6", tags=["week6"])

WORDS = [
    "fresh", "local", "organic", "classic", "spicy", "sweet", "crispy", "golden",
    "tropical", "smoked", "roasted", "light", "rich", "creamy", "zesty", "herbal",
]
TAGS = ["new", "sale", "popular", "seasonal", "limited", "vegan", "imported", "bundle"]
LIST_SIZE = 20
LIST_SEED = 6


def _make_item(rng: random.Random, i: int) -> dict:
    return {
        "id": i,
        "name": f"Item {i}",
        "description": " ".join(rng.choice(WORDS) for _ in range(8)),
        "price": round(rng.uniform(1, 500), 2),
        "tags": rng.sample(TAGS, 3),
        "updated_at": f"2026-10-{rng.randint(1, 28):02d}T{rng.randint(0, 23):02d}:00:00Z",
    }


@lru_cache(maxsize=8)
def _items_json(n: int, seed: int) -> bytes:
    """Same n and seed -> byte-identical payload, generated once and cached."""
    rng = random.Random(seed)
    items = [_make_item(rng, i) for i in range(1, n + 1)]
    return json.dumps(items, separators=(",", ":")).encode("utf-8")


def _json(body: bytes) -> Response:
    return Response(body, media_type="application/json; charset=utf-8")


@router.get("/items")
def list_items():
    """Small list used by the Items screen and the tests."""
    return _json(_items_json(LIST_SIZE, LIST_SEED))


@router.get("/items/{item_id}")
async def get_item(item_id: int, delay_ms: int = Query(0, ge=0, le=10000)):
    """One item. delay_ms simulates a slow server (used in Part 2)."""
    if not 1 <= item_id <= LIST_SIZE:
        raise HTTPException(status_code=404, detail="Item not found")
    await asyncio.sleep(delay_ms / 1000)
    items = json.loads(_items_json(LIST_SIZE, LIST_SEED))
    return items[item_id - 1]


@router.get("/bulk")
def bulk(n: int = Query(5000, ge=1, le=100000), seed: int = 6):
    """Large payload for the Part 3 performance experiment."""
    return _json(_items_json(n, seed))


app = FastAPI(title="MCS4302 Week 6 (standalone)")
app.include_router(router)
