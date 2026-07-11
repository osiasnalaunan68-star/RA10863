import re
from typing import Literal

from fastapi import APIRouter, Query
from app.db.database import get_connection

router = APIRouter(prefix="/api", tags=["search"])

# Matches: "102", "section 102", "sec 102", "sec. 102", "§102", "102(a)", "section 102(uu)"
_SECTION_REF_RE = re.compile(
    r'^\s*(?:sec(?:tion)?s?\.?|§)?\s*(\d+[a-zA-Z\-]*)\s*(\([a-zA-Z0-9]+\))?\s*$',
    re.IGNORECASE,
)
# Matches: "chapter 3", "ch. 3", "chapter II-1"
_CHAPTER_REF_RE = re.compile(
    r'^\s*(?:ch(?:apter)?s?\.?)\s*([0-9ivxlcIVXLC\-]+)\s*$',
    re.IGNORECASE,
)
# Matches: "title II", "title 2"
_TITLE_REF_RE = re.compile(
    r'^\s*(?:title)\s*([0-9ivxlcIVXLC\-]+)\s*$',
    re.IGNORECASE,
)


def _row_to_result(row) -> dict:
    keys = row.keys()
    return {
        "node_id": row["node_id"],
        "node_type": row["node_type"],
        "node_number": row["node_number"],
        "title": row["title"],
        "excerpt": row["excerpt"] or (row["content"][:200] if "content" in keys and row["content"] else ""),
        "title_number": row["title_number"],
        "title_title": row["title_title"],
        "chapter_number": row["chapter_number"],
        "chapter_title": row["chapter_title"],
        "exact_match": bool(row["exact_match"]) if "exact_match" in keys else False,
    }


def _direct_lookup(conn, q: str, filter: str):
    """Resolve queries like '102', 'section 102', 'sec. 102', 'chapter 3',
    'title II' straight against node_number — bypassing full-text search
    entirely so the *actual* Section 102 always outranks a page that merely
    mentions "Section 102" somewhere in its text."""
    node_type = None
    number = None

    m = _SECTION_REF_RE.match(q)
    if m and filter in ("all", "section"):
        node_type, number = "section", m.group(1)
    if node_type is None:
        m = _CHAPTER_REF_RE.match(q)
        if m and filter in ("all", "chapter"):
            node_type, number = "chapter", m.group(1)
    if node_type is None:
        m = _TITLE_REF_RE.match(q)
        if m and filter in ("all", "title"):
            node_type, number = "title", m.group(1)

    if node_type is None or not number:
        return []

    row = conn.execute(
        """
        SELECT n.id AS node_id, n.node_type, n.node_number, n.title, n.content,
               substr(n.content, 1, 220) AS excerpt,
               t_parent.node_number AS title_number, t_parent.title AS title_title,
               ch_parent.node_number AS chapter_number, ch_parent.title AS chapter_title,
               1 AS exact_match
        FROM legal_nodes n
        LEFT JOIN legal_nodes ch_parent ON ch_parent.id = n.parent_id AND ch_parent.node_type = 'chapter'
        LEFT JOIN legal_nodes t_parent ON t_parent.id = ch_parent.parent_id AND t_parent.node_type = 'title'
        WHERE n.node_type = ? AND n.node_number = ?
        LIMIT 1
        """,
        (node_type, number),
    ).fetchone()
    return [row] if row else []


@router.get("/search")
def search(
    q: str = Query(..., min_length=1),
    filter: Literal["all", "title", "chapter", "section"] = Query("all"),
    limit: int = Query(50, ge=1, le=200),
):
    conn = get_connection()
    try:
        q_clean = q.strip()
        results = []
        seen_ids = set()

        # 1. Exact structural match always wins the top spot.
        for row in _direct_lookup(conn, q_clean, filter):
            results.append(_row_to_result(row))
            seen_ids.add((row["node_type"], row["node_id"]))

        # 2. Weighted full-text search as the general keyword fallback.
        #    Tokens are AND-ed (not forced into one rigid phrase like before),
        #    and node_number/title matches are weighted far above raw content
        #    so structural hits outrank incidental mentions.
        tokens = re.findall(r"\w+", q_clean)
        if tokens:
            match_expr = " ".join(f'"{t}"' for t in tokens)
            sql = """
                SELECT s.node_id, n.node_type, n.node_number, n.title, n.content,
                       snippet(search_index, 4, '[', ']', '...', 20) AS excerpt,
                       t_parent.node_number AS title_number, t_parent.title AS title_title,
                       ch_parent.node_number AS chapter_number, ch_parent.title AS chapter_title,
                       0 AS exact_match
                FROM search_index s
                JOIN legal_nodes n ON n.id = s.node_id
                LEFT JOIN legal_nodes ch_parent ON ch_parent.id = n.parent_id AND ch_parent.node_type = 'chapter'
                LEFT JOIN legal_nodes t_parent ON t_parent.id = ch_parent.parent_id AND t_parent.node_type = 'title'
                WHERE search_index MATCH ?
            """
            params = [match_expr]
            if filter != "all":
                sql += " AND n.node_type = ?"
                params.append(filter)
            sql += " ORDER BY bm25(search_index, 12.0, 6.0, 1.0, 4.0) LIMIT ?"
            params.append(limit)

            try:
                rows = conn.execute(sql, params).fetchall()
            except Exception:
                rows = []

            if not rows:
                and_conditions = []
                all_params = []
                for token in tokens:
                    like = f"%{token}%"
                    and_conditions.append(
                        "(n.node_number LIKE ? OR n.title LIKE ? OR n.content LIKE ? OR n.node_type LIKE ?)"
                    )
                    all_params.extend([like, like, like, like])

                sql = f"""
                    SELECT n.id AS node_id, n.node_type, n.node_number, n.title, n.content,
                           substr(n.content, 1, 200) AS excerpt,
                           t_parent.node_number AS title_number, t_parent.title AS title_title,
                           ch_parent.node_number AS chapter_number, ch_parent.title AS chapter_title,
                           0 AS exact_match
                    FROM legal_nodes n
                    LEFT JOIN legal_nodes ch_parent ON ch_parent.id = n.parent_id AND ch_parent.node_type = 'chapter'
                    LEFT JOIN legal_nodes t_parent ON t_parent.id = ch_parent.parent_id AND t_parent.node_type = 'title'
                    WHERE {' AND '.join(and_conditions)}
                """
                params = all_params
                if filter != "all":
                    sql += " AND n.node_type = ?"
                    params.append(filter)
                sql += " ORDER BY n.node_type, CAST(n.node_number AS INTEGER) LIMIT ?"
                params.append(limit)
                rows = conn.execute(sql, params).fetchall()

            for row in rows:
                key = (row["node_type"], row["node_id"])
                if key in seen_ids:
                    continue
                seen_ids.add(key)
                results.append(_row_to_result(row))
                if len(results) >= limit:
                    break

        return results[:limit]
    finally:
        conn.close()
