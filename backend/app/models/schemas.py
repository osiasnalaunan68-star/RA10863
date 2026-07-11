from typing import List, Optional
from pydantic import BaseModel


class CrossReferenceOut(BaseModel):
    text: str
    url: Optional[str] = None


class NodeOut(BaseModel):
    id: int
    uuid: str
    node_type: str
    node_number: Optional[str]
    title: Optional[str]
    content: Optional[str]
    status: str
    version: int
    keywords: List[str] = []
    cross_references: List[CrossReferenceOut] = []
    notes: List[str] = []
    children: List["NodeOut"] = []


NodeOut.model_rebuild()


class ChapterListItem(BaseModel):
    id: int
    node_number: Optional[str]
    title: Optional[str]
    section_count: int
    created_at: str
    updated_at: str
