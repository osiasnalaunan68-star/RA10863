from typing import List, Optional
from app.db.database import get_connection
from app.models.schemas import ChapterListItem, NodeOut, CrossReferenceOut
from app.repositories.node_repository import NodeRepository


class ChapterNotFoundError(Exception):
    pass

def roman_to_int(s: str) -> int:
    # ... (unchanged)
    s = s.upper().strip()
    values = {'I':1, 'V':5, 'X':10, 'L':50, 'C':100}
    total = 0
    prev = 0
    for ch in reversed(s):
        cur = values.get(ch, 0)
        if cur < prev:
            total -= cur
        else:
            total += cur
        prev = cur
    return total if total > 0 else 0


class ChapterService:
    def list_titles_with_chapters(self) -> List[dict]:
        # ... (unchanged from previous version)
        conn = get_connection()
        try:
            titles = conn.execute(
                "SELECT * FROM legal_nodes WHERE node_type = 'title'"
            ).fetchall()
            result = []
            for title in titles:
                chapters = conn.execute(
                    """
                    SELECT c.id, c.node_number, c.title, c.created_at, c.updated_at,
                           COUNT(s.id) as section_count
                    FROM legal_nodes c
                    LEFT JOIN legal_nodes s ON s.parent_id = c.id AND s.node_type = 'section'
                    WHERE c.parent_id = ? AND c.node_type = 'chapter'
                    GROUP BY c.id
                    ORDER BY CAST(c.node_number AS INTEGER) ASC
                    """,
                    (title["id"],),
                ).fetchall()
                if chapters:
                    result.append({
                        "title_id": title["id"],
                        "title_number": title["node_number"],
                        "title_title": title["title"],
                        "chapters": [
                            ChapterListItem(
                                id=ch["id"],
                                node_number=ch["node_number"],
                                title=ch["title"],
                                section_count=ch["section_count"],
                                created_at=ch["created_at"],
                                updated_at=ch["updated_at"],
                            )
                            for ch in chapters
                        ],
                    })
            result.sort(key=lambda t: roman_to_int(t["title_number"]))
            root_chapters = conn.execute(
                """
                SELECT c.id, c.node_number, c.title, c.created_at, c.updated_at,
                       COUNT(s.id) as section_count
                FROM legal_nodes c
                LEFT JOIN legal_nodes s ON s.parent_id = c.id AND s.node_type = 'section'
                WHERE c.node_type = 'chapter' AND c.parent_id IS NULL
                GROUP BY c.id
                ORDER BY CAST(c.node_number AS INTEGER) ASC
                """
            ).fetchall()
            if root_chapters:
                result.append({
                    "title_id": None,
                    "title_number": None,
                    "title_title": "Chapters (no title)",
                    "chapters": [
                        ChapterListItem(
                            id=ch["id"],
                            node_number=ch["node_number"],
                            title=ch["title"],
                            section_count=ch["section_count"],
                            created_at=ch["created_at"],
                            updated_at=ch["updated_at"],
                        )
                        for ch in root_chapters
                    ],
                })
            return result
        finally:
            conn.close()

    def get_chapter(self, chapter_number: str, title_number: Optional[str] = None) -> NodeOut:
        conn = get_connection()
        try:
            repo = NodeRepository(conn)
            if title_number:
                title_row = repo.type_number_exists("title", title_number)
                if not title_row:
                    raise ChapterNotFoundError(f"Title {title_number} not found")
                chapter = repo.chapter_exists_under_title(title_row["id"], chapter_number)
            else:
                chapter = repo.chapter_exists_under_title(None, chapter_number)
            if chapter is None:
                raise ChapterNotFoundError(f"Chapter {chapter_number} not found")
            return self._build_node_out(repo, chapter)
        finally:
            conn.close()

    def _build_node_out(self, repo: NodeRepository, row) -> NodeOut:
        children = [self._build_node_out(repo, c) for c in repo.get_children(row["id"])]
        xrefs = repo.get_cross_references(row["id"])
        cross_refs_out = [CrossReferenceOut(text=x["text"], url=x["url"]) for x in xrefs]
        return NodeOut(
            id=row["id"], uuid=row["uuid"], node_type=row["node_type"],
            node_number=row["node_number"], title=row["title"], content=row["content"],
            status=row["status"], version=row["version"],
            keywords=repo.get_keywords(row["id"]),
            cross_references=cross_refs_out,
            notes=repo.get_notes(row["id"]),
            children=children,
        )
