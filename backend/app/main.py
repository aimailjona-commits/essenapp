import logging

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app import web
from app.api import router

logging.basicConfig(level=logging.INFO)  # u.a. KI-Kosten je Aufruf (planner)

app = FastAPI(title="Essenapp")
app.include_router(router)
app.include_router(web.router)
app.mount("/static", StaticFiles(directory=web.DIR / "static"), name="static")


@app.get("/health")
def health():
    return {"status": "ok"}
