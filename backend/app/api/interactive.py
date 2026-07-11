import json
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.core.security import require_edit_access
from app.db.database import get_connection
from app.repositories.highlight_repository import HighlightRepository
from app.repositories.node_repository import NodeRepository

router = APIRouter(prefix="/api", tags=["interactive"])


# ---------- Highlights ----------
class HighlightCreate(BaseModel):
    node_id: int
    start_offset: int
    end_offset: int
    color: str = "#90EE90"

class HighlightOut(BaseModel):
    id: int
    node_id: int
    start_offset: int
    end_offset: int
    color: str
    created_at: str

@router.get("/highlights/{chapter_number}")
def get_highlights(chapter_number: str):
    conn = get_connection()
    try:
        node_repo = NodeRepository(conn)
        chapter = node_repo.type_number_exists("chapter", chapter_number)
        if not chapter:
            raise HTTPException(status_code=404, detail="Chapter not found")
        highlight_repo = HighlightRepository(conn)
        rows = highlight_repo.get_highlights_for_chapter(chapter["id"])
        return [HighlightOut(**dict(r)) for r in rows]
    finally:
        conn.close()

@router.post("/highlights", response_model=HighlightOut)
def create_highlight(hl: HighlightCreate):
    conn = get_connection()
    try:
        node_repo = NodeRepository(conn)
        node = node_repo.get_by_id(hl.node_id)
        if not node:
            raise HTTPException(status_code=404, detail="Node not found")
        if hl.start_offset < 0 or hl.end_offset > len(node["content"] or ""):
            raise HTTPException(status_code=400, detail="Offsets out of range")
        highlight_repo = HighlightRepository(conn)
        hl_id = highlight_repo.add_highlight(hl.node_id, hl.start_offset, hl.end_offset, hl.color)
        conn.commit()
        created = highlight_repo.get_highlights_for_node(hl.node_id)
        for r in created:
            if r["id"] == hl_id:
                return HighlightOut(**dict(r))
        raise HTTPException(status_code=500, detail="Highlight creation failed")
    finally:
        conn.close()

@router.delete("/highlights/{highlight_id}")
def delete_highlight(highlight_id: int):
    conn = get_connection()
    try:
        highlight_repo = HighlightRepository(conn)
        highlight_repo.delete_highlight(highlight_id)
        conn.commit()
        return {"success": True}
    finally:
        conn.close()

@router.put("/highlights/{highlight_id}")
def update_highlight(highlight_id: int, start_offset: int, end_offset: int):
    conn = get_connection()
    try:
        highlight_repo = HighlightRepository(conn)
        highlight_repo.update_highlight(highlight_id, start_offset, end_offset)
        conn.commit()
        return {"success": True}
    finally:
        conn.close()


# ---------- Node content update (now versioned via node_history) ----------
class NodeUpdate(BaseModel):
    content: str = Field(..., min_length=1)
    created_by: Optional[str] = None

@router.put("/nodes/{node_id}")
def update_node_content(node_id: int, update: NodeUpdate, _: None = Depends(require_edit_access)):
    conn = get_connection()
    try:
        node_repo = NodeRepository(conn)
        node = node_repo.get_by_id(node_id)
        if not node:
            raise HTTPException(status_code=404, detail="Node not found")

        snapshot = json.dumps(
            {"content": node["content"], "title": node["title"], "version": node["version"]},
            ensure_ascii=False,
        )
        node_repo.record_history(node_id, node["version"], snapshot, "update", update.created_by)

        conn.execute(
            "UPDATE legal_nodes SET content = ?, version = version + 1, updated_at = datetime('now') WHERE id = ?",
            (update.content, node_id),
        )
        conn.commit()
        return {"success": True, "message": "Content updated"}
    finally:
        conn.close()

@router.get("/highlights/node/{node_id}", response_model=list[HighlightOut])
def get_highlights_for_node(node_id: int):
    conn = get_connection()
    try:
        highlight_repo = HighlightRepository(conn)
        rows = highlight_repo.get_highlights_for_node(node_id)
        return [HighlightOut(**dict(r)) for r in rows]
    finally:
        conn.close()
