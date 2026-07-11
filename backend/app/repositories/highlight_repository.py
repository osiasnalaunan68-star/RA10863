import sqlite3
from typing import List


class HighlightRepository:
    def __init__(self, conn: sqlite3.Connection):
        self.conn = conn

    def add_highlight(self, node_id: int, start: int, end: int, color: str = "#90EE90") -> int:
        cursor = self.conn.execute(
            "INSERT INTO highlights (node_id, start_offset, end_offset, color) VALUES (?, ?, ?, ?)",
            (node_id, start, end, color),
        )
        return cursor.lastrowid

    def get_highlights_for_node(self, node_id: int) -> List[sqlite3.Row]:
        return self.conn.execute(
            "SELECT * FROM highlights WHERE node_id = ? ORDER BY start_offset",
            (node_id,),
        ).fetchall()

    def get_highlights_for_chapter(self, chapter_id: int) -> List[sqlite3.Row]:
        # Get all descendant node IDs, then fetch highlights
        ids = self.conn.execute(
            """
            WITH RECURSIVE subtree(id) AS (
                SELECT id FROM legal_nodes WHERE id = ?
                UNION ALL
                SELECT legal_nodes.id FROM legal_nodes
                JOIN subtree ON legal_nodes.parent_id = subtree.id
            )
            SELECT id FROM subtree
            """,
            (chapter_id,),
        ).fetchall()
        if not ids:
            return []
        node_ids = [row["id"] for row in ids]
        placeholders = ",".join("?" for _ in node_ids)
        return self.conn.execute(
            f"SELECT * FROM highlights WHERE node_id IN ({placeholders}) ORDER BY node_id, start_offset",
            node_ids,
        ).fetchall()

    def delete_highlight(self, highlight_id: int) -> None:
        self.conn.execute("DELETE FROM highlights WHERE id = ?", (highlight_id,))

    def update_highlight(self, highlight_id: int, start: int, end: int) -> None:
        self.conn.execute(
            "UPDATE highlights SET start_offset = ?, end_offset = ? WHERE id = ?",
            (start, end, highlight_id),
        )
