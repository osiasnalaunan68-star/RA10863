import os
import logging
from fastapi import FastAPI
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware

from app.api import chapters, interactive, search

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Customs Law API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(chapters.router, prefix="/api", tags=["chapters"])
app.include_router(interactive.router, prefix="/api", tags=["interactive"])
app.include_router(search.router, prefix="/api", tags=["search"])

DIST_DIR = os.path.abspath("dist") if os.path.exists("dist") else None

if DIST_DIR:
    app.mount("/assets", StaticFiles(directory="dist/assets"), name="assets")
    logger.info(f"✅ Static assets mounted from {DIST_DIR}/assets")
else:
    logger.warning("⚠️ dist folder not found. Frontend will return 404s.")

@app.get("/{path:path}")
async def serve_react(path: str):
    if path.startswith("api/"):
        return JSONResponse(status_code=404, content={"detail": f"API endpoint not found: /{path}"})
        
    if not DIST_DIR:
        return JSONResponse(status_code=404, content={"detail": "Frontend build not found. Run 'npm run build'."})
        
    candidate = os.path.abspath(os.path.join(DIST_DIR, path))
    if path and candidate.startswith(DIST_DIR) and os.path.isfile(candidate):
        return FileResponse(candidate)
        
    return FileResponse(os.path.join(DIST_DIR, "index.html"))
