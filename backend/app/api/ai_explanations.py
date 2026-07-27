import json
from pathlib import Path
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/api", tags=["ai_explanations"])
DATA_DIR = Path(__file__).parent.parent / "data"
DATA_DIR.mkdir(exist_ok=True)
EXPLANATIONS_FILE = DATA_DIR / "ai_explanations.json"
if not EXPLANATIONS_FILE.exists():
    EXPLANATIONS_FILE.write_text("{}")

class ExplanationsUpdate(BaseModel):
    data: dict

@router.get("/ai_explanations")
async def get_explanations():
    try:
        return json.loads(EXPLANATIONS_FILE.read_text(encoding="utf-8"))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.put("/ai_explanations")
async def update_explanations(update: ExplanationsUpdate):
    try:
        with open(EXPLANATIONS_FILE, "w", encoding="utf-8") as f:
            json.dump(update.data, f, indent=2, ensure_ascii=False)
        # Also sync to frontend static file
        frontend_file = Path(__file__).parent.parent.parent.parent / "frontend" / "src" / "data" / "aiExplanations.json"
        if frontend_file.parent.exists():
            frontend_file.write_text(json.dumps(update.data, indent=2, ensure_ascii=False), encoding="utf-8")
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
