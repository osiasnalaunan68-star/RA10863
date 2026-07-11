import sqlite3
from contextlib import contextmanager

from app.core.config import settings
from app.db.schema import SCHEMA_SQL, DEFAULT_SETTINGS


def get_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(settings.DATABASE_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA busy_timeout = 5000")
    return conn


@contextmanager
def db_transaction():
    conn = get_connection()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _column_exists(conn: sqlite3.Connection, table: str, column: str) -> bool:
    rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
    return any(row["name"] == column for row in rows)


def _migrate(conn: sqlite3.Connection) -> None:
    """Patch older databases created before url/display_text existed on
    node_cross_references. CREATE TABLE IF NOT EXISTS never adds columns to
    a table that already exists, so this runs on every startup and is a
    no-op once the columns are present."""
    if not _column_exists(conn, "node_cross_references", "url"):
        conn.execute("ALTER TABLE node_cross_references ADD COLUMN url TEXT")
    if not _column_exists(conn, "node_cross_references", "display_text"):
        conn.execute("ALTER TABLE node_cross_references ADD COLUMN display_text TEXT")


def init_db() -> None:
    conn = get_connection()
    try:
        conn.executescript(SCHEMA_SQL)
        _migrate(conn)
        for key, value in DEFAULT_SETTINGS.items():
            conn.execute(
                "INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)",
                (key, value),
            )
        conn.commit()
    finally:
        conn.close()
