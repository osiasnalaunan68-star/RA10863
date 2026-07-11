SCHEMA_SQL = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS legal_nodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    parent_id INTEGER,
    node_type TEXT NOT NULL CHECK(node_type IN ('title','chapter','section','paragraph','subparagraph','item')),
    node_number TEXT,
    title TEXT,
    content TEXT,
    path TEXT NOT NULL,
    depth INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'published' CHECK(status IN ('draft','published','archived')),
    version INTEGER NOT NULL DEFAULT 1,
    source TEXT,
    effective_date TEXT,
    created_by TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (parent_id) REFERENCES legal_nodes(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_nodes_uuid ON legal_nodes(uuid);
CREATE INDEX IF NOT EXISTS idx_nodes_parent ON legal_nodes(parent_id);
CREATE INDEX IF NOT EXISTS idx_nodes_type ON legal_nodes(node_type);
CREATE INDEX IF NOT EXISTS idx_nodes_number ON legal_nodes(node_number);
CREATE INDEX IF NOT EXISTS idx_nodes_path ON legal_nodes(path);

-- New unique indexes (replace old idx_unique_type_number)
DROP INDEX IF EXISTS idx_unique_type_number;
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_title ON legal_nodes(node_number) WHERE node_type = 'title';
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_section ON legal_nodes(node_number) WHERE node_type = 'section';
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_chapter ON legal_nodes(parent_id, node_number) WHERE node_type = 'chapter';

CREATE TABLE IF NOT EXISTS node_keywords (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    node_id INTEGER NOT NULL,
    keyword TEXT NOT NULL,
    FOREIGN KEY (node_id) REFERENCES legal_nodes(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_keywords_node ON node_keywords(node_id);
CREATE INDEX IF NOT EXISTS idx_keywords_keyword ON node_keywords(keyword);

CREATE TABLE IF NOT EXISTS node_cross_references (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    node_id INTEGER NOT NULL,
    reference_text TEXT NOT NULL,
    referenced_node_id INTEGER,
    url TEXT,
    display_text TEXT,
    note TEXT,
    FOREIGN KEY (node_id) REFERENCES legal_nodes(id) ON DELETE CASCADE,
    FOREIGN KEY (referenced_node_id) REFERENCES legal_nodes(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_xref_node ON node_cross_references(node_id);

CREATE TABLE IF NOT EXISTS node_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    node_id INTEGER NOT NULL,
    note_text TEXT NOT NULL,
    created_by TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (node_id) REFERENCES legal_nodes(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_notes_node ON node_notes(node_id);

CREATE TABLE IF NOT EXISTS node_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    node_id INTEGER NOT NULL,
    version INTEGER NOT NULL,
    snapshot_json TEXT NOT NULL,
    change_type TEXT NOT NULL CHECK(change_type IN ('create','update','replace','merge','delete')),
    changed_by TEXT,
    changed_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (node_id) REFERENCES legal_nodes(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_history_node ON node_history(node_id);

CREATE TABLE IF NOT EXISTS import_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    duration_ms INTEGER,
    import_mode TEXT NOT NULL CHECK(import_mode IN ('create','replace','merge')),
    chapter_number TEXT,
    title_number TEXT,
    sections_imported INTEGER DEFAULT 0,
    nodes_created INTEGER DEFAULT 0,
    nodes_updated INTEGER DEFAULT 0,
    status TEXT NOT NULL CHECK(status IN ('success','failed','partial')),
    error_message TEXT,
    search_index_time_ms INTEGER,
    created_by TEXT,
    file_name TEXT
);
CREATE INDEX IF NOT EXISTS idx_import_logs_status ON import_logs(status);
CREATE INDEX IF NOT EXISTS idx_import_logs_started ON import_logs(started_at);

CREATE TABLE IF NOT EXISTS backups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    backup_type TEXT NOT NULL CHECK(backup_type IN ('sqlite','json')),
    file_path TEXT NOT NULL,
    reason TEXT,
    chapter_number TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
    node_id UNINDEXED,
    node_type UNINDEXED,
    node_number,
    title,
    content,
    keywords
);

CREATE TABLE IF NOT EXISTS highlights (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    node_id INTEGER NOT NULL,
    start_offset INTEGER NOT NULL,
    end_offset INTEGER NOT NULL,
    color TEXT NOT NULL DEFAULT '#90EE90',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (node_id) REFERENCES legal_nodes(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_highlights_node ON highlights(node_id);
"""

DEFAULT_SETTINGS = {
    "dev_panel_enabled": "true",
    "debug_mode": "false",
    "auto_backup": "true",
    "auto_search_index": "true",
    "preview_required": "false",
    "overwrite_mode": "create",
}
