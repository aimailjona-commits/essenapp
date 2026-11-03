import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app import api, jobs, web
from app.api import router
from app.core.config import settings

logging.basicConfig(level=logging.INFO)  # u.a. KI-Kosten je Aufruf (planner)



@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.scheduler:  # lokal bis zum VPS (E47); dort läuft der Scheduler als eigener Container
        jobs.start()
    yield


app = FastAPI(title="Kochpilot", lifespan=lifespan)
app.include_router(router)
app.include_router(web.router)
app.mount("/static", StaticFiles(directory=web.DIR / "static"), name="static")
api.MEDIA.mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory=api.MEDIA), name="media")  # Rezeptfotos (3), später Schritt-Bilder (9)


@app.get("/health")
def health():
    return {"status": "ok"}
