import sqlite3
import uuid as uuid_lib
from typing import List, Optional


class NodeRepository:
    def __init__(self, conn: sqlite3.Connection):
        self.conn = conn

    def type_number_exists(self, node_type: str, node_number: str) -> Optional[sqlite3.Row]:
        return self.conn.execute(
            "SELECT * FROM legal_nodes WHERE node_type = ? AND node_number = ?",
            (node_type, node_number),
        ).fetchone()

    def get_by_id(self, node_id: int) -> Optional[sqlite3.Row]:
        return self.conn.execute(
            "SELECT * FROM legal_nodes WHERE id = ?", (node_id,)
        ).fetchone()

    def get_children(self, parent_id: Optional[int]) -> List[sqlite3.Row]:
        if parent_id is None:
            return self.conn.execute(
                "SELECT * FROM legal_nodes WHERE parent_id IS NULL ORDER BY sort_order ASC"
            ).fetchall()
        return self.conn.execute(
            "SELECT * FROM legal_nodes WHERE parent_id = ? ORDER BY sort_order ASC",
            (parent_id,),
        ).fetchall()

    def get_subtree_ids(self, root_id: int) -> List[int]:
        rows = self.conn.execute(
            """
            WITH RECURSIVE subtree(id) AS (
                SELECT id FROM legal_nodes WHERE id = ?
                UNION ALL
                SELECT legal_nodes.id FROM legal_nodes
                JOIN subtree ON legal_nodes.parent_id = subtree.id
            )
            SELECT id FROM subtree
            """,
            (root_id,),
        ).fetchall()
        return [row["id"] for row in rows]

    def insert_node(
        self,
        parent_id: Optional[int],
        node_type: str,
        node_number: Optional[str],
        title: Optional[str],
        content: Optional[str],
        depth: int,
        sort_order: int,
        status: str = "published",
        version: int = 1,
        source: Optional[str] = None,
        effective_date: Optional[str] = None,
        created_by: Optional[str] = None,
    ) -> int:
        node_uuid = str(uuid_lib.uuid4())
        cursor = self.conn.execute(
            """
            INSERT INTO legal_nodes
                (uuid, parent_id, node_type, node_number, title, content,
                 path, depth, sort_order, status, version, source,
                 effective_date, created_by)
            VALUES (?, ?, ?, ?, ?, ?, '', ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                node_uuid, parent_id, node_type, node_number, title, content,
                depth, sort_order, status, version, source,
                effective_date, created_by,
            ),
        )
        new_id = cursor.lastrowid
        if parent_id is None:
            path = str(new_id)
        else:
            parent = self.get_by_id(parent_id)
            path = f"{parent['path']}.{new_id}"
        self.conn.execute("UPDATE legal_nodes SET path = ? WHERE id = ?", (path, new_id))
        return new_id

    def delete_node(self, node_id: int) -> None:
        self.conn.execute("DELETE FROM legal_nodes WHERE id = ?", (node_id,))

    def add_keyword(self, node_id: int, keyword: str) -> None:
        self.conn.execute(
            "INSERT INTO node_keywords (node_id, keyword) VALUES (?, ?)", (node_id, keyword)
        )

    def add_cross_reference(self, node_id: int, reference_text: str, url: str = None, display_text: str = None) -> None:
        self.conn.execute(
            "INSERT INTO node_cross_references (node_id, reference_text, url, display_text) VALUES (?, ?, ?, ?)",
            (node_id, reference_text, url, display_text),
        )

    def add_note(self, node_id: int, note_text: str, created_by: Optional[str]) -> None:
        self.conn.execute(
            "INSERT INTO node_notes (node_id, note_text, created_by) VALUES (?, ?, ?)",
            (node_id, note_text, created_by),
        )

    def get_keywords(self, node_id: int) -> List[str]:
        rows = self.conn.execute(
            "SELECT keyword FROM node_keywords WHERE node_id = ?", (node_id,)
        ).fetchall()
        return [row["keyword"] for row in rows]

    def get_cross_references(self, node_id: int) -> List[dict]:
        rows = self.conn.execute(
            "SELECT reference_text, url, display_text FROM node_cross_references WHERE node_id = ?",
            (node_id,),
        ).fetchall()
        result = []
        for row in rows:
            text = row["display_text"] or row["reference_text"]
            url = row["url"]
            result.append({"text": text, "url": url})
        return result

    def get_notes(self, node_id: int) -> List[str]:
        rows = self.conn.execute(
            "SELECT note_text FROM node_notes WHERE node_id = ?", (node_id,)
        ).fetchall()
        return [row["note_text"] for row in rows]

    def record_history(
        self, node_id: int, version: int, snapshot_json: str, change_type: str, changed_by: Optional[str]
    ) -> None:
        self.conn.execute(
            """
            INSERT INTO node_history (node_id, version, snapshot_json, change_type, changed_by)
            VALUES (?, ?, ?, ?, ?)
            """,
            (node_id, version, snapshot_json, change_type, changed_by),
        )

    def counts_by_type(self) -> dict:
        rows = self.conn.execute(
            "SELECT node_type, COUNT(*) as c FROM legal_nodes GROUP BY node_type"
        ).fetchall()
        return {row["node_type"]: row["c"] for row in rows}

    def total_nodes(self) -> int:
        row = self.conn.execute("SELECT COUNT(*) as c FROM legal_nodes").fetchone()
        return row["c"]

    def chapter_exists_under_title(self, title_id: Optional[int], chapter_number: str) -> Optional[sqlite3.Row]:
        if title_id is None:
            return self.conn.execute(
                "SELECT * FROM legal_nodes WHERE node_type='chapter' AND node_number=? AND parent_id IS NULL",
                (chapter_number,)
            ).fetchone()
        return self.conn.execute(
            "SELECT * FROM legal_nodes WHERE node_type='chapter' AND node_number=? AND parent_id=?",
            (chapter_number, title_id)
        ).fetchone()

    def clear_cross_references(self, node_id: int) -> None:
        self.conn.execute("DELETE FROM node_cross_references WHERE node_id = ?", (node_id,))
