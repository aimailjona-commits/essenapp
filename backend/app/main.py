import logging

from fastapi import FastAPI

from app.api import router

logging.basicConfig(level=logging.INFO)  # u.a. KI-Kosten je Aufruf (planner)

app = FastAPI(title="Essenapp")
app.include_router(router)


@app.get("/health")
def health():
    return {"status": "ok"}
