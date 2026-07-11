import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.db.database import init_db

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("customs_law")

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    logger.info("Database ready at %s", settings.DATABASE_PATH)
    yield

app = FastAPI(title="Customs Law Platform - RA 10863", lifespan=lifespan)

# CORS
origins = ["*"] if settings.CORS_ORIGINS.strip() == "*" else [o.strip() for o in settings.CORS_ORIGINS.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
def health():
    return {"status": "ok"}

# Diagnostic endpoint (para malaman kung gumagana ang API)
@app.get("/api/test")
async def test_api():
    return {"message": "API is working"}

# Import routers
try:
    from app.api import chapters as chapters_router
    logger.info("✅ chapters router imported")
except Exception as e:
    logger.error(f"❌ chapters import error: {e}")
    raise

try:
    from app.api import search as search_router
    logger.info("✅ search router imported")
except Exception as e:
    logger.error(f"❌ search import error: {e}")
    raise

try:
    from app.api import interactive as interactive_router
    logger.info("✅ interactive router imported")
except Exception as e:
    logger.error(f"❌ interactive import error: {e}")
    raise

# Isama ang routers na may prefix na "/api"
app.include_router(chapters_router.router, prefix="/api")
app.include_router(search_router.router, prefix="/api")
app.include_router(interactive_router.router, prefix="/api")
logger.info("✅ All routers included with /api prefix")

# I-log ang lahat ng routes pagkatapos ng startup
@app.on_event("startup")
async def log_routes():
    logger.info("=== REGISTERED ROUTES ===")
    for route in app.routes:
        methods = getattr(route, "methods", set())
        logger.info(f"  {route.path} - {methods}")
    logger.info("==========================")

# Serve static files
if os.path.exists("dist"):
    DIST_DIR = os.path.abspath("dist")
    app.mount("/assets", StaticFiles(directory="dist/assets"), name="assets")
    logger.info(f"✅ Static assets mounted from {DIST_DIR}/assets")
else:
    logger.warning("⚠️ dist folder not found")

# Catch-all for SPA (dapat nasa huli)
@app.get("/{path:path}")
async def serve_react(path: str):
    # Kung ang path ay nagsisimula sa "api/", magbalik ng 404 JSON (hindi HTML)
    if path.startswith("api/"):
        return JSONResponse(
            status_code=404,
            content={"detail": f"API endpoint not found: /{path}"}
        )
    # Serve real files (manifest.json, sw.js, icons, etc.)
    candidate = os.path.abspath(os.path.join(DIST_DIR, path))
    if path and candidate.startswith(DIST_DIR) and os.path.isfile(candidate):
        return FileResponse(candidate)
    # Fallback to index.html para sa SPA
    return FileResponse("dist/index.html")
