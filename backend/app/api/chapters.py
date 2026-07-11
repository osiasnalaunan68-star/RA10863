from typing import Optional
from fastapi import APIRouter, HTTPException, Query

from app.services.chapter_service import ChapterService, ChapterNotFoundError

router = APIRouter()
chapter_service = ChapterService()

@router.get("/titles")
async def get_titles():
    """Return all titles with their chapters and section counts."""
    return chapter_service.list_titles_with_chapters()

@router.get("/chapter/{chapter_number}")
async def get_chapter(chapter_number: str, title_number: Optional[str] = Query(None)):
    """Return a chapter tree with all its sections and subsections."""
    try:
        return chapter_service.get_chapter(chapter_number, title_number)
    except ChapterNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
