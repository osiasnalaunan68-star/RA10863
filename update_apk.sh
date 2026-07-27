#!/bin/bash
# ==============================================================
# UPDATE APK VERSION WITH WEBSITE FEATURES (NO DEV PANEL FOR USERS)
# Run this in the root directory (where frontend/ and android/ exist)
# ==============================================================

set -e  # stop on error

echo "🚀 Starting APK update..."

# Create directories if missing
mkdir -p frontend/src/components
mkdir -p frontend/src/data
mkdir -p frontend/src/pages

# -------------------------------------------------------------------
# 1.  OVERWRITE EXISTING FILES WITH NEW VERSIONS (from website)
# -------------------------------------------------------------------

# ---------- frontend/src/db.js ----------
cat > frontend/src/db.js << 'EOF'
import initSqlJs from 'sql.js/dist/sql-wasm.js';
import sqlWasmUrl from 'sql.js/dist/sql-wasm.wasm?url';

let dbPromise = null;

async function loadDatabase() {
  const SQL = await initSqlJs({ locateFile: () => sqlWasmUrl });
  const url = `${import.meta.env.BASE_URL}customs_law.db`;
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Could not load customs_law.db (HTTP ${response.status})`);
  const arrayBuffer = await response.arrayBuffer();
  return new SQL.Database(new Uint8Array(arrayBuffer));
}

export function initDatabase() {
  if (!dbPromise) dbPromise = loadDatabase();
  return dbPromise;
}

export async function query(sql, params = []) {
  const database = await initDatabase();
  const stmt = database.prepare(sql);
  stmt.bind(params);
  const results = [];
  while (stmt.step()) results.push(stmt.getAsObject());
  stmt.free();
  return results;
}

export async function queryOne(sql, params = []) {
  const rows = await query(sql, params);
  return rows.length ? rows[0] : null;
}

function romanToInt(s) {
  if (!s) return 0;
  s = String(s).toUpperCase().trim();
  const values = { I: 1, V: 5, X: 10, L: 50, C: 100, D: 500, M: 1000 };
  let total = 0;
  let prev = 0;
  for (let i = s.length - 1; i >= 0; i--) {
    const cur = values[s[i]] || 0;
    total += cur < prev ? -cur : cur;
    prev = cur;
  }
  return total;
}

export async function getTitles() {
  const rows = await query(`
    SELECT 
      t.id AS title_id,
      t.node_number AS title_number,
      t.title AS title_title,
      c.id AS chapter_id,
      c.node_number AS chapter_number,
      c.title AS chapter_title,
      (SELECT COUNT(*) FROM legal_nodes s WHERE s.parent_id = c.id AND s.node_type = 'section') AS section_count
    FROM legal_nodes t
    LEFT JOIN legal_nodes c ON c.parent_id = t.id AND c.node_type = 'chapter'
    WHERE t.node_type = 'title'
    ORDER BY CAST(c.node_number AS INTEGER) ASC
  `);
  const map = new Map();
  for (const row of rows) {
    if (!map.has(row.title_id)) {
      map.set(row.title_id, {
        title_id: row.title_id,
        title_number: row.title_number,
        title_title: row.title_title,
        chapters: []
      });
    }
    if (row.chapter_id) {
      map.get(row.title_id).chapters.push({
        id: row.chapter_id,
        node_number: row.chapter_number,
        title: row.chapter_title,
        section_count: row.section_count
      });
    }
  }
  const rootRows = await query(`
    SELECT 
      c.id AS chapter_id,
      c.node_number AS chapter_number,
      c.title AS chapter_title,
      (SELECT COUNT(*) FROM legal_nodes s WHERE s.parent_id = c.id AND s.node_type = 'section') AS section_count
    FROM legal_nodes c
    WHERE c.node_type = 'chapter' AND c.parent_id IS NULL
    ORDER BY CAST(c.node_number AS INTEGER) ASC
  `);
  const result = Array.from(map.values()).sort(
    (a, b) => romanToInt(a.title_number) - romanToInt(b.title_number)
  );
  if (rootRows.length) {
    result.push({
      title_id: null,
      title_number: null,
      title_title: "Chapters (no title)",
      chapters: rootRows.map(r => ({
        id: r.chapter_id,
        node_number: r.chapter_number,
        title: r.chapter_title,
        section_count: r.section_count
      }))
    });
  }
  return result;
}

export async function getChapter(chapterNumber, titleNumber = null) {
  let whereClause = "node_type = 'chapter' AND node_number = ?";
  let params = [chapterNumber];
  if (titleNumber) {
    const titleRow = await queryOne("SELECT id FROM legal_nodes WHERE node_type = 'title' AND node_number = ?", [titleNumber]);
    if (!titleRow) return null;
    whereClause += " AND parent_id = ?";
    params.push(titleRow.id);
  } else {
    whereClause += " AND parent_id IS NULL";
  }
  const chapterRow = await queryOne(`SELECT * FROM legal_nodes WHERE ${whereClause}`, params);
  if (!chapterRow) return null;

  const sql = `
    WITH RECURSIVE subtree(id, parent_id, node_type, node_number, title, content, status, version, depth, sort_order) AS (
      SELECT id, parent_id, node_type, node_number, title, content, status, version, depth, sort_order
      FROM legal_nodes WHERE id = ?
      UNION ALL
      SELECT n.id, n.parent_id, n.node_type, n.node_number, n.title, n.content, n.status, n.version, n.depth, n.sort_order
      FROM legal_nodes n JOIN subtree s ON n.parent_id = s.id
    )
    SELECT * FROM subtree ORDER BY depth, sort_order
  `;
  const rows = await query(sql, [chapterRow.id]);
  const nodeMap = {};
  const root = { ...chapterRow, children: [] };
  nodeMap[chapterRow.id] = root;
  for (const row of rows) {
    if (row.id === chapterRow.id) continue;
    const parent = nodeMap[row.parent_id];
    if (!parent) continue;
    const node = { ...row, children: [] };
    parent.children.push(node);
    nodeMap[row.id] = node;
  }
  const ids = Object.keys(nodeMap);
  if (ids.length) {
    const keywordRows = await query(`SELECT node_id, keyword FROM node_keywords WHERE node_id IN (${ids.join(',')})`);
    for (const kw of keywordRows) {
      const node = nodeMap[kw.node_id];
      if (node) { if (!node.keywords) node.keywords = []; node.keywords.push(kw.keyword); }
    }
    const xrefRows = await query(`SELECT node_id, reference_text, url, display_text FROM node_cross_references WHERE node_id IN (${ids.join(',')})`);
    for (const xr of xrefRows) {
      const node = nodeMap[xr.node_id];
      if (node) { if (!node.cross_references) node.cross_references = []; node.cross_references.push({ text: xr.display_text || xr.reference_text, url: xr.url }); }
    }
    const noteRows = await query(`SELECT node_id, note_text FROM node_notes WHERE node_id IN (${ids.join(',')})`);
    for (const nt of noteRows) {
      const node = nodeMap[nt.node_id];
      if (node) { if (!node.notes) node.notes = []; node.notes.push(nt.note_text); }
    }
  }
  function buildNode(node) {
    return {
      id: node.id,
      uuid: node.uuid || '',
      node_type: node.node_type,
      node_number: node.node_number,
      title: node.title,
      content: node.content,
      status: node.status,
      version: node.version,
      keywords: node.keywords || [],
      cross_references: node.cross_references || [],
      notes: node.notes || [],
      children: (node.children || []).map(child => buildNode(child))
    };
  }
  return buildNode(root);
}

// Fetch the FULL subtree of an entire Title — used to build the AI/quiz
// generation prompt for a whole title in one paste.
export async function getTitleTree(titleNumber) {
  const titleRow = await queryOne(
    "SELECT * FROM legal_nodes WHERE node_type = 'title' AND node_number = ?",
    [titleNumber]
  );
  if (!titleRow) return null;

  const sql = `
    WITH RECURSIVE subtree(id, parent_id, node_type, node_number, title, content, depth, sort_order) AS (
      SELECT id, parent_id, node_type, node_number, title, content, depth, sort_order
      FROM legal_nodes WHERE id = ?
      UNION ALL
      SELECT n.id, n.parent_id, n.node_type, n.node_number, n.title, n.content, n.depth, n.sort_order
      FROM legal_nodes n JOIN subtree s ON n.parent_id = s.id
    )
    SELECT * FROM subtree ORDER BY depth, sort_order
  `;
  const rows = await query(sql, [titleRow.id]);
  const nodeMap = {};
  const root = { ...titleRow, children: [] };
  nodeMap[titleRow.id] = root;
  for (const row of rows) {
    if (row.id === titleRow.id) continue;
    const parent = nodeMap[row.parent_id];
    if (!parent) continue;
    const node = { ...row, children: [] };
    parent.children.push(node);
    nodeMap[row.id] = node;
  }
  function buildNode(node) {
    return {
      id: node.id,
      node_type: node.node_type,
      node_number: node.node_number,
      title: node.title,
      content: node.content,
      children: (node.children || []).map(buildNode)
    };
  }
  return buildNode(root);
}

// ---------- Search ----------

function escapeRegExp(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Builds a short excerpt centered on the FIRST match in the content (instead
// of always showing characters 1-200, which usually cut off the actual
// match), and wraps every matched token with [ ] so SearchResultCard can
// turn them into <mark> highlights.
function buildExcerpt(content, tokens, radius = 90) {
  if (!content) return '';
  const lower = content.toLowerCase();
  let matchIndex = -1;
  let matchLen = 0;
  for (const token of tokens) {
    const idx = lower.indexOf(token.toLowerCase());
    if (idx !== -1 && (matchIndex === -1 || idx < matchIndex)) {
      matchIndex = idx;
      matchLen = token.length;
    }
  }
  let start = 0;
  let end = Math.min(content.length, 200);
  if (matchIndex !== -1) {
    start = Math.max(0, matchIndex - radius);
    end = Math.min(content.length, matchIndex + matchLen + radius);
  }
  let excerpt = content.slice(start, end);
  if (start > 0) excerpt = `…${excerpt}`;
  if (end < content.length) excerpt = `${excerpt}…`;

  const sortedTokens = [...tokens].sort((a, b) => b.length - a.length);
  for (const token of sortedTokens) {
    if (!token) continue;
    const re = new RegExp(`(${escapeRegExp(token)})`, 'gi');
    excerpt = excerpt.replace(re, '[$1]');
  }
  return excerpt;
}

// ✅ FIXED search — no FTS (this sql.js build doesn't have it), uses LIKE.
export async function search(queryText, filter = 'all', limit = 50) {
  const trimmedQuery = queryText.trim();
  const tokens = trimmedQuery.split(/\s+/).filter(t => t.length > 0);
  if (!tokens.length) return [];

  const likeConditions = tokens.map(() =>
    '(n.node_number LIKE ? OR n.title LIKE ? OR n.content LIKE ?)'
  ).join(' OR ');

  const likeParams = [];
  for (const token of tokens) {
    const like = `%${token}%`;
    likeParams.push(like, like, like);
  }

  let sql = `
    SELECT
      n.id AS node_id,
      n.node_type,
      n.node_number,
      n.title,
      n.content,
      t_parent.node_number AS title_number,
      t_parent.title AS title_title,
      ch_parent.node_number AS chapter_number,
      ch_parent.title AS chapter_title
    FROM legal_nodes n
    LEFT JOIN legal_nodes ch_parent ON ch_parent.id = n.parent_id AND ch_parent.node_type = 'chapter'
    LEFT JOIN legal_nodes t_parent ON t_parent.id = ch_parent.parent_id AND t_parent.node_type = 'title'
    WHERE ${likeConditions}
  `;

  if (filter !== 'all') {
    sql += " AND n.node_type = ?";
    likeParams.push(filter);
  }

  sql += " ORDER BY n.node_type, CAST(n.node_number AS INTEGER)";

  const rows = await query(sql, likeParams);
  const lowerQuery = trimmedQuery.toLowerCase();

  const withMeta = rows.map((row) => {
    const haystacks = [row.node_number, row.title, row.content]
      .filter(Boolean)
      .map((s) => String(s).toLowerCase());
    const exact_match = haystacks.some((h) => h.includes(lowerQuery)) ? 1 : 0;
    return {
      ...row,
      excerpt: buildExcerpt(row.content || '', tokens),
      exact_match,
    };
  });

  // Stable sort: exact matches float to the top; everything else keeps the
  // node_type/node_number order the SQL query already gave it.
  withMeta.sort((a, b) => b.exact_match - a.exact_match);

  return withMeta.slice(0, limit);
}

export async function getChapterForNode(nodeId) {
  const sql = `
    WITH RECURSIVE ancestors(id, parent_id, node_type, node_number) AS (
      SELECT id, parent_id, node_type, node_number
      FROM legal_nodes
      WHERE id = ?
      UNION ALL
      SELECT n.id, n.parent_id, n.node_type, n.node_number
      FROM legal_nodes n
      JOIN ancestors a ON n.id = a.parent_id
    )
    SELECT node_type, node_number, id
    FROM ancestors
    WHERE node_type = 'chapter'
    LIMIT 1
  `;
  const result = await queryOne(sql, [nodeId]);
  if (!result) return null;

  const titleSql = `
    SELECT t.node_number AS title_number
    FROM legal_nodes t
    WHERE t.id = (
      SELECT parent_id FROM legal_nodes WHERE id = ? AND node_type = 'chapter'
    )
    AND t.node_type = 'title'
  `;
  const titleRow = await queryOne(titleSql, [result.id]);
  return {
    chapter_number: result.node_number,
    title_number: titleRow ? titleRow.title_number : null
  };
}

const HIGHLIGHTS_KEY = 'customsLaw_highlights';
export function getHighlightsForNode(nodeId) {
  try { const all = JSON.parse(localStorage.getItem(HIGHLIGHTS_KEY) || '{}'); return all[nodeId] || []; } catch { return []; }
}
export function addHighlight(nodeId, start, end, color = '#90EE90') {
  const all = JSON.parse(localStorage.getItem(HIGHLIGHTS_KEY) || '{}');
  if (!all[nodeId]) all[nodeId] = [];
  const newHl = { id: Date.now() + Math.random() * 1000, node_id: nodeId, start_offset: start, end_offset: end, color, created_at: new Date().toISOString() };
  all[nodeId].push(newHl);
  localStorage.setItem(HIGHLIGHTS_KEY, JSON.stringify(all));
  return newHl;
}
export function removeHighlight(highlightId) {
  const all = JSON.parse(localStorage.getItem(HIGHLIGHTS_KEY) || '{}');
  for (const nodeId in all) {
    all[nodeId] = all[nodeId].filter(h => h.id !== highlightId);
    if (all[nodeId].length === 0) delete all[nodeId];
  }
  localStorage.setItem(HIGHLIGHTS_KEY, JSON.stringify(all));
}

// ---------- Notes ----------
const NOTES_KEY = 'customsLaw_notes';

export function getNotesForNode(nodeId) {
  try {
    const all = JSON.parse(localStorage.getItem(NOTES_KEY) || '{}');
    return all[nodeId] || [];
  } catch {
    return [];
  }
}

export function addNote(nodeId, content) {
  const all = JSON.parse(localStorage.getItem(NOTES_KEY) || '{}');
  if (!all[nodeId]) all[nodeId] = [];
  const now = new Date().toISOString();
  const note = {
    id: Date.now() + Math.random() * 1000,
    node_id: nodeId,
    content,
    created_at: now,
    updated_at: now,
  };
  all[nodeId].push(note);
  localStorage.setItem(NOTES_KEY, JSON.stringify(all));
  return note;
}

export function updateNote(nodeId, noteId, content) {
  const all = JSON.parse(localStorage.getItem(NOTES_KEY) || '{}');
  const list = all[nodeId] || [];
  const note = list.find((n) => n.id === noteId);
  if (note) {
    note.content = content;
    note.updated_at = new Date().toISOString();
    localStorage.setItem(NOTES_KEY, JSON.stringify(all));
  }
  return note || null;
}

export function deleteNote(nodeId, noteId) {
  const all = JSON.parse(localStorage.getItem(NOTES_KEY) || '{}');
  if (!all[nodeId]) return;
  all[nodeId] = all[nodeId].filter((n) => n.id !== noteId);
  if (all[nodeId].length === 0) delete all[nodeId];
  localStorage.setItem(NOTES_KEY, JSON.stringify(all));
}

// ---------- Resume Reading / Study Progress ----------
const PROGRESS_KEY = 'customsLaw_lastPosition';

export function saveProgress(progress) {
  try {
    const existing = JSON.parse(localStorage.getItem(PROGRESS_KEY) || '{}');
    const merged = { ...existing, ...progress, saved_at: new Date().toISOString() };
    localStorage.setItem(PROGRESS_KEY, JSON.stringify(merged));
  } catch {}
}

export function getProgress() {
  try {
    return JSON.parse(localStorage.getItem(PROGRESS_KEY) || 'null');
  } catch {
    return null;
  }
}

// ---------- Tutorial ----------
const TUTORIAL_KEY = 'customsLaw_tutorialSeen';

export function hasTutorialBeenSeen() {
  try {
    return localStorage.getItem(TUTORIAL_KEY) === 'true';
  } catch {
    return true;
  }
}

export function markTutorialSeen() {
  try {
    localStorage.setItem(TUTORIAL_KEY, 'true');
  } catch {}
}
EOF

# ---------- frontend/src/main.jsx ----------
cat > frontend/src/main.jsx << 'EOF'
import "./index.css";
import React from "react";
import ReactDOM from "react-dom/client";
import ChapterBrowser from "./pages/ChapterBrowser";

class ErrorBoundary extends React.Component {
  constructor(props) { super(props); this.state = { error: null }; }
  static getDerivedStateFromError(e) { return { error: e }; }
  componentDidCatch(e, info) { console.error(e, info); }
  render() {
    if (this.state.error) {
      return (
        <div style={{ padding: 20, background: "#1e1e1e", color: "#ff6b6b", fontFamily: "monospace", whiteSpace: "pre-wrap", minHeight: "100vh" }}>
          <h1>⚠️ App Error</h1>
          <pre>{this.state.error.toString()}</pre>
        </div>
      );
    }
    return this.props.children;
  }
}

window.addEventListener("unhandledrejection", (e) => {
  const msg = e.reason?.message || String(e.reason);
  document.body.innerHTML = `<div style="padding:20px;background:#1e1e1e;color:#ff6b6b;font-family:monospace;white-space:pre-wrap;">⚠️ ${msg}</div>`;
});

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <ErrorBoundary>
      <ChapterBrowser />
    </ErrorBoundary>
  </React.StrictMode>
);

// Register Service Worker
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./sw.js").catch((err) => {
      console.warn("Service worker registration failed:", err);
    });
  });
}
EOF

# ---------- frontend/src/index.css ----------
cat > frontend/src/index.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

# ---------- frontend/src/env.js ----------
cat > frontend/src/env.js << 'EOF'
// Single source of truth for "is this a local dev build" checks (e.g. to hide
// the Dev Panel from the production build shipped to GitHub Pages). Vite
// replaces import.meta.env.DEV with a literal `false` in production builds,
// so anything gated behind IS_DEV never renders for real users.
export const IS_DEV = import.meta.env.DEV;
EOF

# ---------- frontend/src/aiContext.js ----------
cat > frontend/src/aiContext.js << 'EOF'
import aiContextData from "./data/aiContext.json";

// Osias 6.7 — bundled AI explanations, shipped fully offline with the app.
// All entries are pre-generated and permanently baked into data/aiContext.json,
// so this is now just a simple, read-only lookup. (There used to be a
// companion "Dev Panel" import tool for pasting in fresh AI-generated batches
// during authoring — that workflow is finished, so it was removed to keep the
// shipped app lean and to avoid exposing any import/edit control to users.)

export function getAiContext(nodeId) {
  return aiContextData[String(nodeId)] || null;
}

export const AI_APPS = [
  { id: "meta", label: "Meta AI", icon: "💬", url: "https://m.me/MetaAI" },
  { id: "chatgpt", label: "ChatGPT", icon: "🟢", url: "https://chatgpt.com/" },
  { id: "gemini", label: "Gemini", icon: "✨", url: "https://gemini.google.com/app" },
];

export async function copyPromptAndOpen(prompt, appUrl) {
  try {
    await navigator.clipboard.writeText(prompt);
  } catch {
    // Clipboard can silently fail on some Android WebViews.
  }
  window.open(appUrl, "_blank", "noopener,noreferrer");
}
EOF

# ---------- frontend/src/quizStore.js ----------
cat > frontend/src/quizStore.js << 'EOF'
// Quiz storage: lets you paste AI-generated quiz JSON (per title/level) and have
// it saved permanently in localStorage. When importing multiple batches with
// the same _title, entries are MERGED instead of overwritten.
//
// Title label: optional. Add a top-level "_title" key in the pasted JSON
// (e.g. { "_title": "CMTA Title I - Level 1 Batch", "393": {...} }) to name the batch.
// Importing Level 2 with the same _title will merge with Level 1.
// Matching is case-insensitive and ignores leading/trailing spaces, so
// "Title I" and "title i " will merge into the same batch instead of
// silently creating a duplicate one.

const STORE_KEY = "customsLaw_quizImports";

function emptyStore() {
  return { batches: {}, entries: {} };
}

function loadStore() {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    if (!raw) return emptyStore();
    const parsed = JSON.parse(raw);
    return {
      batches: parsed.batches || {},
      entries: parsed.entries || {}
    };
  } catch {
    return emptyStore();
  }
}

function saveStore(store) {
  localStorage.setItem(STORE_KEY, JSON.stringify(store));
}

function normalizeLabel(label) {
  return String(label || "").trim().toLowerCase();
}

export function getImportedQuizEntry(nodeId) {
  const store = loadStore();
  return store.entries[String(nodeId)] || null;
}

export function getAllQuizBatches() {
  const store = loadStore();
  return Object.values(store.batches).sort((a, b) => b.importedAt.localeCompare(a.importedAt));
}

export function getQuizBatchEntries(batchId) {
  const store = loadStore();
  const batch = store.batches[batchId];
  if (!batch) return [];
  return batch.nodeIds.map((id) => ({ id, ...(store.entries[id] || {}) }));
}

// Flattens batches + entries into { id: { _title, level1, level2, ... } } —
// the SAME shape used by the shipped frontend/src/data/quizData.json static
// file. This is the fix for the "everything shows up as Untitled" bug: the
// title now travels with each question instead of only living on the batch,
// so the live import preview and the final baked-in file always agree.
export function getFlattenedEntries() {
  const store = loadStore();
  const flat = {};
  for (const batch of Object.values(store.batches)) {
    for (const id of batch.nodeIds) {
      if (store.entries[id]) {
        flat[id] = { _title: batch.label, ...store.entries[id] };
      }
    }
  }
  return flat;
}

export function importQuizJson(jsonText) {
  const parsed = JSON.parse(jsonText);
  const rawLabel = parsed._title;
  if (parsed._title !== undefined) delete parsed._title;
  const ids = Object.keys(parsed);
  if (!ids.length) throw new Error("The pasted JSON is empty.");

  const store = loadStore();

  let existingBatchId = null;
  const label = (rawLabel && String(rawLabel).trim()) || null;

  if (label) {
    const normalized = normalizeLabel(label);
    for (const [bId, batch] of Object.entries(store.batches)) {
      if (normalizeLabel(batch.label) === normalized) {
        existingBatchId = bId;
        break;
      }
    }
  }

  for (const id of ids) {
    const existing = store.entries[id];
    store.entries[id] = existing ? { ...existing, ...parsed[id] } : parsed[id];
  }

  if (existingBatchId) {
    const batch = store.batches[existingBatchId];
    const existingIds = new Set(batch.nodeIds);
    for (const id of ids) {
      if (!existingIds.has(id)) batch.nodeIds.push(id);
    }
    batch.importedAt = new Date().toISOString();
  } else {
    const batchId = `qb_${Date.now()}`;
    const fallback = `Import – ${new Date().toLocaleString("en-PH", {
      month: "short", day: "numeric", hour: "numeric", minute: "2-digit",
    })}`;
    store.batches[batchId] = {
      id: batchId,
      label: label || fallback,
      importedAt: new Date().toISOString(),
      nodeIds: ids
    };
  }

  saveStore(store);

  const count = Object.keys(store.entries).length;
  return { count, label: label || "New batch" };
}

export function renameQuizBatch(batchId, newLabel) {
  const store = loadStore();
  if (!store.batches[batchId]) return;
  const trimmed = newLabel.trim();
  if (trimmed) store.batches[batchId].label = trimmed;
  saveStore(store);
}

export function updateQuizEntry(nodeId, fields) {
  const store = loadStore();
  if (!store.entries[nodeId]) return;
  store.entries[nodeId] = { ...store.entries[nodeId], ...fields };
  saveStore(store);
}

export function deleteQuizEntry(nodeId) {
  const store = loadStore();
  delete store.entries[nodeId];
  for (const bId in store.batches) {
    store.batches[bId].nodeIds = store.batches[bId].nodeIds.filter((id) => id !== nodeId);
    if (store.batches[bId].nodeIds.length === 0) delete store.batches[bId];
  }
  saveStore(store);
}

export function deleteQuizBatch(batchId) {
  const store = loadStore();
  const batch = store.batches[batchId];
  if (!batch) return;
  for (const id of batch.nodeIds) {
    let usedElsewhere = false;
    for (const [bId, b] of Object.entries(store.batches)) {
      if (bId !== batchId && b.nodeIds.includes(id)) { usedElsewhere = true; break; }
    }
    if (!usedElsewhere) delete store.entries[id];
  }
  delete store.batches[batchId];
  saveStore(store);
}

export function getQuizExportAllJson() {
  return JSON.stringify(getFlattenedEntries(), null, 2);
}

export function saveRawQuizEntries(jsonText) {
  const parsed = JSON.parse(jsonText);
  const store = loadStore();
  for (const id of Object.keys(parsed)) {
    const existing = store.entries[id];
    store.entries[id] = existing ? { ...existing, ...parsed[id] } : parsed[id];
  }
  saveStore(store);
}

export function clearAllQuizImports() {
  saveStore(emptyStore());
}

export function getQuizImportedCount() {
  return Object.keys(loadStore().entries).length;
}
EOF

# ---------- frontend/src/quizContext.js ----------
cat > frontend/src/quizContext.js << 'EOF'
// Quiz generation — builds the "Copy Quiz Template" clipboard payload for one Title.
// The prompt instructs the AI to SELECTIVELY generate quiz questions for the most
// important and testable provisions, like a professor curating an exam.
//
// Flow: tap the 📝 button next to a Title in the sidebar -> this builds a
// prompt containing instructions + the full text of every node in that
// title, each tagged with its unique ID -> paste into an AI -> paste the
// AI's JSON answer into Dev Panel -> Import Quiz JSON.

function flattenForQuiz(node, lines = []) {
  const label = `${(node.node_type || "").toUpperCase()} ${node.node_number || ""}`.trim();
  const heading = node.title ? `${label} — ${node.title}` : label;
  if (node.content) {
    lines.push(`[ID: ${node.id}] ${heading}`);
    lines.push(node.content.trim());
    lines.push("");
  } else if (node.title) {
    lines.push(`[ID: ${node.id}] ${heading}`);
    lines.push("");
  }
  if (node.children) {
    for (const child of node.children) flattenForQuiz(child, lines);
  }
  return lines;
}

function collectQuizIds(node, ids = []) {
  if (node.content) ids.push(node.id);
  if (node.children) {
    for (const child of node.children) collectQuizIds(child, ids);
  }
  return ids;
}

export const QUIZ_MASTER_PROMPT = `🧠 QUIZ GENERATION — SELECTIVE & CUBLE-ALIGNED (CMTA RA 10863)

You are an expert Customs law professor and CuBLE exam developer. Your task is to create a high-quality, selective 5-level quiz system for a Philippine law-study app covering RA 10863, the Customs Modernization and Tariff Act (CMTA).

🎯 TARGET AUDIENCE: BSCA students and Customs Broker Licensure Examination (CuBLE) reviewees.
🔍 SOURCE: The official CMTA text provided below. Do NOT invent facts not stated in the text.
🌐 WEB SEARCH: You MAY use web search (if available) to verify CuBLE exam patterns, frequently tested topics, and board exam trends — but your answers must ALWAYS be based on the actual CMTA text provided.

---
📋 SELECTION RULE — YOU ARE THE PROFESSOR

You are given a list of IDs and their full text below.

Your task is to SELECTIVELY generate quiz questions for the MOST IMPORTANT and TESTABLE provisions — just like a professor would when designing a board exam review.

DO NOT generate a question for every single ID.
DO NOT force questions for repetitive, minor, or purely procedural provisions.

CHOOSE the provisions that are:
- Frequently tested in CuBLE (e.g., definitions, penalties, procedures, exceptions)
- Core principles (Declaration of Policy, Definition of Terms, Importation rules)
- Thresholds, percentages, deadlines (e.g., 15 days, 30 days, 100% ad valorem)
- Key distinctions (Abatement vs Refund, Entry vs Admission, Outright vs Technical Smuggling)
- Practical application scenarios (seizure, forfeiture, assessment, protest)
- Board exam favorite topics (Flexible Clause, AEO, Rules of Origin, Valuation Methods)
- Unique or landmark provisions

SKIP provisions that are:
- Purely procedural or administrative (e.g., reporting requirements, record-keeping)
- Repetitive or redundant across multiple sections
- Too minor or rarely tested in board exams
- Already covered by a more important provision

The number of questions you generate should be based on the educational importance and testability of the provisions — there is no fixed minimum or maximum. Focus on quality over quantity. A good exam covers the most critical topics without being exhaustive.

IMPORTANT: Whichever IDs you choose to cover for THIS Title, reuse that SAME set of IDs across every level (1 through 5) if you are asked to generate more than one level later for this Title. This keeps every level's question count consistent.

---
📋 CRITICAL: THE "_title" FIELD MUST STAY IDENTICAL ACROSS ALL 5 LEVELS

This app merges quiz batches by matching the "_title" string EXACTLY (case-insensitive, whitespace-trimmed only — no other normalization). If Level 1, Level 2, Level 3, Level 4, and Level 5 are generated as separate outputs for the SAME Title, every single output MUST use the exact same "_title" value. Do NOT append "Level 1", "Batch 2", "Easy", "Normal", etc. to it, and do NOT reword it between levels. Otherwise the app creates separate, duplicate-looking groups instead of one merged quiz set with all 5 level buttons working correctly.

Derive the "_title" from the Title heading found at the top of the FULL TEXT section below (e.g. a line like "TITLE I — PRELIMINARY PROVISIONS" becomes "_title": "Title I – Preliminary Provisions"). If the person tells you to use a specific exact "_title" string, use that instead — it takes priority, since it guarantees the string matches whatever was used for the other levels of this same Title.

---
📋 OUTPUT FORMAT

If asked to generate ONE level at a time (most common), output ONLY that level, nested under each selected ID:

{
  "_title": "Title I – Preliminary Provisions",
  "<selectedID>": {
    "level1": {
      "question": "...",
      "choices": { "A": "...", "B": "...", "C": "...", "D": "..." },
      "correct": "A",
      "reason": "..."
    }
  }
}

If asked to generate ALL 5 levels at once, nest every level under the same ID instead:

{
  "_title": "Title I – Preliminary Provisions",
  "<selectedID>": {
    "level1": { "question": "...", "choices": {...}, "correct": "A", "reason": "..." },
    "level2": { "question": "...", "choices": {...}, "correct": "B", "reason": "..." },
    "level3": { "question": "...", "choices": {...}, "correct": "C", "reason": "..." },
    "level4": { "question": "...", "choices": {...}, "correct": "D", "reason": "..." },
    "level5": { "question": "...", "correct": "The exact answer text", "reason": "..." }
  }
}

Note: Level 5 never has a "choices" field — it is identification-only.

Output ONLY the JSON object. No markdown code fences, no extra commentary before or after it.

---
📋 CRITICAL: THE "reason" FIELD MUST BE PLAIN TEXT — NO MARKDOWN

The app displays "reason" inside a plain paragraph tag with no markdown rendering whatsoever. Do NOT use any of the following inside "reason":
- Bold markers (**text**)
- Blockquote markers (>)
- Headers (#)
- Emoji section icons (book, lightbulb, checkmark, etc.)
- Forced line breaks

Instead, write "reason" as ONE flat, well-punctuated paragraph, 3-4 sentences max, following this structure:

"Correct answer: [letter]. Section [X]([paragraph letter if any]) of the CMTA states: '[exact verbatim wording from the source text].' [1-2 sentence tip explaining the key distinction, common trap, or why the other choices are wrong.]"

Rules:
- Quote the EXACT wording from the source text, inside straight single or double quotes — never paraphrase the legal text itself.
- No icons, no markdown symbols, no forced line breaks — everything flows as normal prose.
- Level 1 reasons are written in Tagalog, but the quoted legal text itself stays in English inside quotes.
- Levels 2-5 reasons are written fully in English.

EXAMPLE (Level 2): "reason": "Correct answer: C. Section 101 of the CMTA states the State's policy is to 'efficiently facilitate international trade,' not restrict it, while also aiming to 'prevent and curtail any form of customs fraud and illegal acts.' Choice C reverses this intent, which contradicts the law's actual goal of facilitation with fraud control."

EXAMPLE (Level 1): "reason": "Tamang sagot: C. Ayon sa Section 101, layunin ng estado na 'efficiently facilitate international trade' o padaliin ang international trade, hindi ito paghigpitan. Mali ang choice C dahil sinasabi nitong dapat limitahan ang import."

---
🎯 LEVEL GUIDE:

🟢 LEVEL 1 — EASY (Tagalog Foundation)
- Language: Tagalog
- Purpose: Build foundation before transitioning to English.
- Question Types: Definition of Terms, True or False (presented as 4 choices), Best Answer, Simple Scenario-Based Questions.
- Example (True or False): "Ang Bureau of Customs ay nasa ilalim ng Department of Finance." Choices: A. True, B. False, C. Partially True, D. Cannot be Determined
- Keep it simple. Focus on basic understanding.

🔵 LEVEL 2 — NORMAL (English Foundation)
- Language: English
- Purpose: Introduce students to the official legal language used in the CMTA and CuBLE.
- Question Types: Definition of Terms, Focus on customs terminology, legal definitions, basic concepts, section identification.
- Keep it straightforward. Test memory and recognition.

🟠 LEVEL 3 — MEDIUM (Legal Analysis)
- Language: English
- Purpose: Develop analytical thinking similar to actual board exam questions.
- Question Types: Best Answer, Focus: Interpretation, Exceptions, Comparing provisions, Applying legal principles.
- Require deeper understanding, not just rote memorization.

🟣 LEVEL 4 — MEDIUM PRO (Real-World Application)
- Language: English
- Purpose: Train students to apply CMTA provisions in realistic customs situations.
- Question Types: Scenario-Based Questions
- Scenarios include: Importation, Exportation, Customs valuation, Tariff classification, Seizure and forfeiture, Customs procedures, Realistic business transactions.
- Make the scenarios practical and relatable to actual customs operations in the Philippines (seaports, airports, PEZA, Clark, Subic, Free Zones).

🔴 LEVEL 5 — WILL DONE (Hard / Mastery Mode)
- Language: English
- Purpose: Measure true mastery without relying on answer choices.
- Question Types: Identification — user manually types the answer.
- Question Types: Definition of Terms, Best Answer, Scenario-Based Questions, Mixed Board-Style Questions.
- The correct answer should be a single, clear, unambiguous term or short phrase.
- The app will handle case-insensitive matching, so the correct answer must be spelled correctly.
- No choices — this tests recall, not recognition.

---
📋 BOARD EXAM INSIGHTS (Use web search if available)

If you have web search capability, use it to verify:
- Which CMTA topics are frequently tested in the CuBLE (Customs Broker Licensure Examination)
- Common board exam question patterns (e.g., "Which is NOT a valid...," "Except...," "What is the correct...,")
- Frequently asked definitions, percentages, deadlines, and distinctions
- Real board exam trends from recent years

Your questions should mimic actual CuBLE question quality and difficulty.

---
📋 IMPORTANT REMINDERS

- DO NOT generate questions for every ID — be selective.
- Choose IDs that are testable, important, and board-exam relevant.
- Use web search (if available) to verify CuBLE exam patterns.
- Your JSON must only include the IDs you selected.
- Skip IDs that are repetitive, procedural, or minor.
- Focus on quality over quantity — there is no fixed number of questions.
- Keep the exact same "_title" across every level you generate for this Title.
- The "reason" field must be plain flat prose — no markdown, no icons, no line breaks.

---
📋 IDs available (you choose which to cover — do not feel obligated to cover all):

IDs to cover: `;

export function copyQuizPromptForTitle(titleTree) {
  const fullText = flattenForQuiz(titleTree).join("\n");
  const ids = collectQuizIds(titleTree);

  return `${QUIZ_MASTER_PROMPT} ${ids.join(", ")}

=== FULL TEXT (use this as your source of truth) ===
${fullText}`;
}

// Legacy export — kept for backward compatibility
export function buildQuizPromptForTitle(titleTree) {
  return copyQuizPromptForTitle(titleTree);
}
EOF

# ---------- frontend/src/components/QuizShared.jsx ----------
cat > frontend/src/components/QuizShared.jsx << 'EOF'
import { useState, useEffect } from "react";

export const LEVELS = [
  { id: "level1", label: "🟢 Level 1 — Easy", tagalog: "Madali", color: "green" },
  { id: "level2", label: "🔵 Level 2 — Normal", tagalog: "Katamtaman", color: "blue" },
  { id: "level3", label: "🟠 Level 3 — Medium", tagalog: "Gitna", color: "orange" },
  { id: "level4", label: "🟣 Level 4 — Medium Pro", tagalog: "Gitnang Pro", color: "purple" },
  { id: "level5", label: "🔴 Level 5 — Will Done", tagalog: "Dalubhasa", color: "red" },
];

const LEVEL_STROKE = { green: "#22c55e", blue: "#3b82f6", orange: "#f97316", purple: "#a855f7", red: "#ef4444" };
const LEVEL_BORDER = {
  green: "border-emerald-400 hover:bg-emerald-50 dark:border-emerald-600 dark:hover:bg-emerald-950/30",
  blue: "border-blue-400 hover:bg-blue-50 dark:border-blue-600 dark:hover:bg-blue-950/30",
  orange: "border-orange-400 hover:bg-orange-50 dark:border-orange-600 dark:hover:bg-orange-950/30",
  purple: "border-purple-400 hover:bg-purple-50 dark:border-purple-600 dark:hover:bg-purple-950/30",
  red: "border-red-400 hover:bg-red-50 dark:border-red-600 dark:hover:bg-red-950/30",
};

export function ProgressCircle({ progress, size = 60, strokeWidth = 6, color = "#22c55e" }) {
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (progress / 100) * circumference;
  return (
    <div className="relative inline-flex items-center justify-center" style={{ width: size, height: size }}>
      <svg className="transform -rotate-90" width={size} height={size}>
        <circle className="text-slate-200 dark:text-slate-700" strokeWidth={strokeWidth} stroke="currentColor" fill="transparent" r={radius} cx={size / 2} cy={size / 2} />
        <circle stroke={color} strokeWidth={strokeWidth} strokeDasharray={circumference} strokeDashoffset={offset} strokeLinecap="round" fill="transparent" r={radius} cx={size / 2} cy={size / 2} className="transition-all duration-500" style={{ stroke: progress > 0 ? color : "transparent" }} />
      </svg>
      <span className="absolute text-sm font-semibold text-slate-700 dark:text-slate-200">{Math.round(progress)}%</span>
    </div>
  );
}

export function QuizLevelButton({ level, progress, onClick }) {
  const colorClass = LEVEL_BORDER[level.color] || LEVEL_BORDER.green;
  return (
    <button onClick={onClick} className={`flex items-center gap-4 rounded-xl border-2 p-4 w-full transition-all ${colorClass}`}>
      <ProgressCircle progress={progress} color={LEVEL_STROKE[level.color] || LEVEL_STROKE.green} />
      <div className="flex-1 text-left">
        <p className="font-semibold text-slate-800 dark:text-slate-100">{level.label}</p>
        <p className="text-sm text-slate-500 dark:text-slate-400">{level.tagalog} · {progress > 0 ? `${Math.round(progress)}% completed` : "Not started"}</p>
      </div>
    </button>
  );
}

export function QuizQuestion({ level, questionData, onAnswer, answered, selected }) {
  const [inputValue, setInputValue] = useState("");
  const isLevel5 = level === "level5";
  const choices = questionData?.choices || {};
  const correct = questionData?.correct || "";
  const reason = questionData?.reason || "";

  const handleChoiceClick = (choiceKey) => { if (!answered) onAnswer(choiceKey); };
  const handleInputSubmit = () => { if (!answered && inputValue.trim()) onAnswer(inputValue.trim()); };

  if (isLevel5) {
    return (
      <div className="space-y-4">
        <p className="text-lg font-medium text-slate-800 dark:text-slate-100">{questionData?.question || "No question available"}</p>
        <p className="text-sm text-slate-500 dark:text-slate-400">Type your answer below:</p>
        <div className="flex gap-2">
          <input type="text" value={inputValue} onChange={(e) => setInputValue(e.target.value)} onKeyDown={(e) => e.key === "Enter" && handleInputSubmit()} disabled={answered} placeholder="Type your answer here..." className="flex-1 rounded-lg border border-slate-200 bg-white px-4 py-2 text-slate-800 focus:outline-none focus:ring-2 focus:ring-navy-900 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100 dark:focus:ring-navy-500 disabled:opacity-50" />
          <button onClick={handleInputSubmit} disabled={answered || !inputValue.trim()} className="rounded-lg bg-navy-900 px-6 py-2 text-sm font-semibold text-white disabled:opacity-40 dark:bg-navy-700">Submit</button>
        </div>
        {answered && (
          <div className={`mt-4 rounded-lg p-4 ${selected === correct ? "bg-emerald-50 dark:bg-emerald-950/30" : "bg-red-50 dark:bg-red-950/30"}`}>
            <p className="font-medium text-slate-800 dark:text-slate-100">{selected === correct ? "✅ Correct!" : `❌ Incorrect. The correct answer is: ${correct}`}</p>
            {reason && <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">{reason}</p>}
          </div>
        )}
      </div>
    );
  }

  const choiceKeys = ["A", "B", "C", "D"];
  return (
    <div className="space-y-4">
      <p className="text-lg font-medium text-slate-800 dark:text-slate-100">{questionData?.question || "No question available"}</p>
      <div className="space-y-2">
        {choiceKeys.map((key) => {
          const label = choices[key] || "";
          const isSelected = selected === key;
          const isCorrect = answered && key === correct;
          const isWrong = answered && isSelected && key !== correct;
          const choiceClass = answered
            ? isCorrect ? "border-emerald-400 bg-emerald-50 dark:border-emerald-600 dark:bg-emerald-950/30"
              : isWrong ? "border-red-400 bg-red-50 dark:border-red-600 dark:bg-red-950/30"
              : "border-slate-200 bg-white dark:border-slate-600 dark:bg-slate-800"
            : isSelected ? "border-navy-900 dark:border-navy-500"
              : "border-slate-200 bg-white hover:border-slate-400 dark:border-slate-600 dark:bg-slate-800 dark:hover:border-slate-400";
          return (
            <button key={key} onClick={() => handleChoiceClick(key)} disabled={answered} className={`block w-full rounded-xl border-2 px-4 py-3 text-left text-sm transition-colors ${choiceClass} ${!answered && "cursor-pointer"} disabled:cursor-default`}>
              <span className="font-semibold">{key}.</span> {label}
            </button>
          );
        })}
      </div>
      {answered && (
        <div className={`mt-4 rounded-lg p-4 ${selected === correct ? "bg-emerald-50 dark:bg-emerald-950/30" : "bg-red-50 dark:bg-red-950/30"}`}>
          <p className="font-medium text-slate-800 dark:text-slate-100">{selected === correct ? "✅ Correct!" : `❌ Incorrect. The correct answer is: ${correct}`}</p>
          {reason && <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">{reason}</p>}
        </div>
      )}
    </div>
  );
}

// progressKey identifies WHERE to save/read progress (localStorage key
// `quiz_progress_${progressKey}`). Pass a stable id — a batch id while
// testing in Dev Panel, or the title string once baked into quizData.json.
export function QuizPlayView({ title, entries, level, onBack, progressKey, backLabel = "← Back" }) {
  const [currentIndex, setCurrentIndex] = useState(0);
  const [answers, setAnswers] = useState({});
  const [progress, setProgress] = useState(0);
  const [score, setScore] = useState(0);

  const nodeIds = Object.keys(entries);
  const totalQuestions = nodeIds.length;
  const currentId = nodeIds[currentIndex] || null;
  const currentEntry = currentId ? entries[currentId] : null;
  const currentQuestion = currentEntry?.[level] || null;
  const currentAnswer = currentId ? answers[currentId] : null;
  const isAnswered = currentAnswer !== undefined && currentAnswer !== null;

  useEffect(() => {
    if (totalQuestions === 0) return;
    const answeredIds = Object.keys(answers).filter((id) => answers[id] !== undefined && answers[id] !== null);
    const progressPct = (answeredIds.length / totalQuestions) * 100;
    setProgress(progressPct);
    const correctCount = answeredIds.filter((id) => entries[id]?.[level]?.correct === answers[id]).length;
    setScore(totalQuestions ? (correctCount / totalQuestions) * 100 : 0);
    if (progressKey) {
      try {
        const key = `quiz_progress_${progressKey}`;
        const saved = JSON.parse(localStorage.getItem(key) || "{}");
        saved[level] = progressPct;
        localStorage.setItem(key, JSON.stringify(saved));
      } catch {}
    }
  }, [answers, totalQuestions, entries, level, progressKey]);

  const handleAnswer = (answer) => { if (currentId && !answers[currentId]) setAnswers((prev) => ({ ...prev, [currentId]: answer })); };
  const goToPrevious = () => { if (currentIndex > 0) setCurrentIndex(currentIndex - 1); };
  const goToNext = () => { if (currentIndex < totalQuestions - 1) setCurrentIndex(currentIndex + 1); };
  const goToQuestion = (index) => setCurrentIndex(index);

  if (totalQuestions === 0) {
    return (
      <div className="flex h-64 flex-col items-center justify-center text-center text-slate-500 dark:text-slate-400">
        <p className="text-lg font-medium">No questions available for this level.</p>
        <p className="text-sm">Try importing quiz data first.</p>
      </div>
    );
  }

  const levelLabel = LEVELS.find((l) => l.id === level)?.label || level;

  return (
    <div>
      <div className="mb-4 flex items-center justify-between">
        <button onClick={onBack} className="flex items-center gap-1 rounded-lg px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100 dark:text-slate-300 dark:hover:bg-slate-800">{backLabel}</button>
        <div className="flex items-center gap-3">
          <span className="text-sm font-medium text-slate-600 dark:text-slate-300">{levelLabel}</span>
          <span className="text-xs text-slate-400 dark:text-slate-500">{currentIndex + 1} / {totalQuestions}</span>
        </div>
      </div>

      {title && (
        <div className="mb-3 text-center">
          <span className="text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">{title}</span>
        </div>
      )}

      <div className="mb-2 flex items-center justify-between text-xs text-slate-500 dark:text-slate-400">
        <span>Progress: {Math.round(progress)}%</span>
        <span>Score: {Math.round(score)}%</span>
      </div>

      <div className="mb-3 h-1 w-full rounded-full bg-slate-100 dark:bg-slate-700">
        <div className="h-1 rounded-full bg-gradient-to-r from-amber-400 to-navy-700 transition-all duration-300 dark:from-amber-500 dark:to-navy-400" style={{ width: `${progress}%` }} />
      </div>

      <div className="mb-4 flex flex-wrap gap-1">
        {nodeIds.map((id, idx) => {
          const isAnsweredDot = answers[id] !== undefined && answers[id] !== null;
          const isActive = idx === currentIndex;
          const q = entries[id]?.[level];
          const isCorrect = answers[id] === q?.correct;
          const dotColor = isAnsweredDot ? (isCorrect ? "bg-emerald-400 dark:bg-emerald-500" : "bg-red-400 dark:bg-red-500") : "bg-slate-300 dark:bg-slate-600";
          return <button key={id} onClick={() => goToQuestion(idx)} className={`h-3 w-3 rounded-full transition-all ${isActive ? "scale-125" : ""} ${dotColor}`} title={`Question ${idx + 1}`} />;
        })}
      </div>

      <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-card dark:border-slate-700 dark:bg-slate-800">
        <QuizQuestion level={level} questionData={currentQuestion} onAnswer={handleAnswer} answered={isAnswered} selected={currentAnswer} />
      </div>

      <div className="mt-4 flex justify-between">
        <button onClick={goToPrevious} disabled={currentIndex === 0} className="rounded-lg border border-slate-200 px-4 py-2 text-sm font-medium text-slate-600 disabled:opacity-40 dark:border-slate-600 dark:text-slate-300">Previous</button>
        <button onClick={goToNext} disabled={currentIndex === totalQuestions - 1} className="rounded-lg border border-slate-200 px-4 py-2 text-sm font-medium text-slate-600 disabled:opacity-40 dark:border-slate-600 dark:text-slate-300">Next</button>
      </div>

      <div className="mt-4 text-center text-xs text-slate-400 dark:text-slate-500">{Math.round(progress)}% complete · {Math.round(score)}% score</div>
    </div>
  );
}
EOF

# ---------- frontend/src/pages/ChapterBrowser.jsx ----------
# (we'll use the full file from the website; ensure IS_DEV gates are present)
cat > frontend/src/pages/ChapterBrowser.jsx << 'EOF'
import { useState, useEffect, useCallback, useRef, useMemo, useContext, createContext } from "react";
import {
  getTitles, getChapter, getTitleTree, search,
  addHighlight, removeHighlight, getHighlightsForNode,
  getNotesForNode, addNote, updateNote, deleteNote,
  saveProgress, getProgress,
  hasTutorialBeenSeen, markTutorialSeen,
  getChapterForNode,
} from "../db";
import {
  getAiContext, AI_APPS, copyPromptAndOpen,
} from "../aiContext";
import { IS_DEV } from "../env";
import { copyQuizPromptForTitle } from "../quizContext";
import DevPanel from "./DevPanel";
import QuizPage from "./QuizPage";

const MODE_KEY = "customsLaw_mode";
const FONT_KEY = "customsLaw_fontScale";
const DARK_KEY = "customsLaw_darkMode";

const HighlightUIContext = createContext(null);
function useHighlightUI() { return useContext(HighlightUIContext); }

function useNodeHighlights(nodeId, shouldLoad) {
  const [highlights, setHighlights] = useState([]);
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    if (!shouldLoad || !nodeId || loaded) return;
    const data = getHighlightsForNode(nodeId);
    setHighlights(data);
    setLoaded(true);
  }, [shouldLoad, nodeId, loaded]);
  const addHighlightLocal = useCallback(async (start, end) => {
    const newHl = addHighlight(nodeId, start, end);
    setHighlights(prev => [...prev, newHl]);
  }, [nodeId]);
  const removeHighlightLocal = useCallback(async (hlId) => {
    removeHighlight(hlId);
    setHighlights(prev => prev.filter(h => h.id !== hlId));
  }, []);
  return { highlights, addHighlight: addHighlightLocal, removeHighlight: removeHighlightLocal };
}

function useNodeNotes(nodeId, shouldLoad) {
  const [notes, setNotes] = useState([]);
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    if (!shouldLoad || !nodeId || loaded) return;
    setNotes(getNotesForNode(nodeId));
    setLoaded(true);
  }, [shouldLoad, nodeId, loaded]);
  const createNote = useCallback((content) => {
    const note = addNote(nodeId, content);
    setNotes((prev) => [...prev, note]);
    return note;
  }, [nodeId]);
  const editNote = useCallback((noteId, content) => {
    const note = updateNote(nodeId, noteId, content);
    setNotes((prev) => prev.map((n) => (n.id === noteId ? note : n)));
  }, [nodeId]);
  const removeNote = useCallback((noteId) => {
    deleteNote(nodeId, noteId);
    setNotes((prev) => prev.filter((n) => n.id !== noteId));
  }, [nodeId]);
  return { notes, createNote, editNote, removeNote };
}

function formatNoteDate(iso) {
  try {
    const d = new Date(iso);
    return d.toLocaleDateString(undefined, { month: "short", day: "numeric" }) +
      " · " + d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  } catch {
    return "";
  }
}

function applyHighlights(text, highlights) {
  if (!highlights || highlights.length === 0) return [{ text, highlightId: null }];
  const sorted = [...highlights].sort((a, b) => a.start_offset - b.start_offset);
  const segments = [];
  let cursor = 0;
  for (const hl of sorted) {
    if (hl.start_offset > cursor) segments.push({ text: text.slice(cursor, hl.start_offset), highlightId: null });
    segments.push({ text: text.slice(hl.start_offset, hl.end_offset), highlightId: hl.id, color: hl.color });
    cursor = hl.end_offset;
  }
  if (cursor < text.length) segments.push({ text: text.slice(cursor), highlightId: null });
  return segments;
}

function SelectionToolbar({ x, y, kind, onSave, onCancel, onDelete }) {
  return (
    <div style={{ position: "fixed", left: x, top: y, zIndex: 100 }} className="flex items-center gap-1 rounded-xl border border-slate-200 bg-white px-1.5 py-1.5 shadow-lg shadow-slate-900/10 dark:border-slate-600 dark:bg-slate-800 dark:shadow-black/40">
      {kind === "existing" ? (
        <>
          <button onClick={onDelete} className="flex items-center gap-1 rounded-lg px-3 py-2 min-h-[40px] text-sm font-medium text-red-600 active:bg-red-50 dark:text-red-400 dark:active:bg-red-950/40">🗑 Remove highlight</button>
          <button onClick={onCancel} className="rounded-lg px-3 py-2 min-h-[40px] text-sm text-slate-500 active:bg-slate-100 dark:text-slate-400 dark:active:bg-slate-700">Close</button>
        </>
      ) : (
        <>
          <button onClick={onSave} className="flex items-center gap-1 rounded-lg bg-amber-100 px-3 py-2 min-h-[40px] text-sm font-semibold text-amber-800 active:bg-amber-200 dark:bg-amber-900/50 dark:text-amber-300 dark:active:bg-amber-900/70">🖍 Highlight</button>
          <button onClick={onCancel} className="rounded-lg px-3 py-2 min-h-[40px] text-sm text-slate-500 active:bg-slate-100 dark:text-slate-400 dark:active:bg-slate-700">Cancel</button>
        </>
      )}
    </div>
  );
}

function HighlightableContent({ nodeId, content, highlights, addHighlight, removeHighlight, className, armed }) {
  const containerRef = useRef(null);
  const [pendingSelection, setPendingSelection] = useState(null);
  const [toolbar, setToolbar] = useState(null);
  useEffect(() => {
    if (!armed) { setPendingSelection(null); setToolbar((t) => (t && t.kind === "existing" ? t : null)); return; }
    const handleSelectionChange = () => {
      const sel = window.getSelection();
      if (!sel || sel.isCollapsed || !containerRef.current || !containerRef.current.contains(sel.anchorNode)) {
        setPendingSelection(null); setToolbar((t) => (t && t.kind === "existing" ? t : null)); return;
      }
      const range = sel.getRangeAt(0);
      const preRange = document.createRange();
      preRange.selectNodeContents(containerRef.current);
      preRange.setEnd(range.startContainer, range.startOffset);
      const start = preRange.toString().length;
      const end = start + range.toString().length;
      if (start >= end) return;
      setPendingSelection({ start, end });
      const rect = range.getBoundingClientRect();
      setToolbar({ x: Math.max(8, Math.min(rect.left, window.innerWidth - 200)), y: rect.bottom + 8, kind: "selection" });
    };
    document.addEventListener("selectionchange", handleSelectionChange);
    return () => document.removeEventListener("selectionchange", handleSelectionChange);
  }, [armed]);
  const handleMarkClick = (e, hlId) => {
    e.stopPropagation();
    const rect = e.target.getBoundingClientRect();
    setToolbar({ x: Math.max(8, Math.min(rect.left, window.innerWidth - 200)), y: rect.bottom + 8, kind: "existing", hlId });
    setPendingSelection(null);
  };
  const closeToolbar = () => { setToolbar(null); setPendingSelection(null); window.getSelection()?.removeAllRanges(); };
  const confirmHighlight = async () => { if (!pendingSelection) return; await addHighlight(pendingSelection.start, pendingSelection.end); closeToolbar(); };
  const confirmDelete = async () => { if (!toolbar?.hlId) return; await removeHighlight(toolbar.hlId); closeToolbar(); };
  const segments = applyHighlights(content, highlights);
  return (
    <div className="relative">
      <div ref={containerRef} className={`${className} ${armed ? "rounded-lg bg-amber-50/70 ring-1 ring-amber-300 dark:bg-amber-950/30 dark:ring-amber-700" : ""}`}>
        {segments.map((seg, i) =>
          seg.highlightId ? (
            <mark key={i} style={{ backgroundColor: seg.color }} className="cursor-pointer rounded-sm px-0.5" onClick={(e) => handleMarkClick(e, seg.highlightId)}>{seg.text}</mark>
          ) : (
            <span key={i}>{seg.text}</span>
          )
        )}
      </div>
      {toolbar && <SelectionToolbar x={toolbar.x} y={toolbar.y} kind={toolbar.kind} onSave={confirmHighlight} onDelete={confirmDelete} onCancel={closeToolbar} />}
    </div>
  );
}

function NotePanel({ notes, onCreate, onEdit, onDelete, onClose }) {
  const [editingId, setEditingId] = useState(null);
  const [draft, setDraft] = useState("");
  const [adding, setAdding] = useState(notes.length === 0);

  const startEdit = (note) => { setEditingId(note.id); setDraft(note.content); setAdding(false); };
  const startAdd = () => { setAdding(true); setEditingId(null); setDraft(""); };
  const cancel = () => { setEditingId(null); setAdding(notes.length === 0); setDraft(""); };
  const save = () => {
    const text = draft.trim();
    if (!text) return;
    if (editingId) { onEdit(editingId, text); setEditingId(null); }
    else { onCreate(text); setAdding(false); }
    setDraft("");
  };

  return (
    <div onClick={(e) => e.stopPropagation()} className="mt-3 rounded-xl border border-sky-200 bg-sky-50/70 p-3 dark:border-sky-800 dark:bg-sky-950/30">
      <div className="mb-2 flex items-center justify-between">
        <span className="text-xs font-semibold uppercase tracking-wide text-sky-700 dark:text-sky-400">📝 My Notes</span>
        <button onClick={onClose} className="rounded-lg px-2 py-1 text-xs font-medium text-slate-500 active:bg-slate-200 dark:text-slate-400 dark:active:bg-slate-700">Close</button>
      </div>
      {notes.length > 0 && !adding && !editingId && (
        <div className="mb-2 space-y-2">
          {notes.map((n) => (
            <div key={n.id} className="rounded-lg bg-white p-2.5 shadow-sm dark:bg-slate-800">
              <p className="whitespace-pre-wrap text-sm text-slate-700 dark:text-slate-200">{n.content}</p>
              <div className="mt-1.5 flex items-center justify-between">
                <span className="text-[11px] text-slate-400 dark:text-slate-500">
                  {n.updated_at !== n.created_at ? `Edited ${formatNoteDate(n.updated_at)}` : `Added ${formatNoteDate(n.created_at)}`}
                </span>
                <div className="flex gap-3">
                  <button onClick={() => startEdit(n)} className="text-xs font-semibold text-sky-700 dark:text-sky-400">Edit</button>
                  <button onClick={() => onDelete(n.id)} className="text-xs font-semibold text-red-600 dark:text-red-400">Delete</button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
      {adding || editingId ? (
        <div>
          <textarea
            autoFocus
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Write your own explanation or reminder…"
            rows={3}
            style={{ fontSize: "16px" }}
            className="w-full rounded-lg border border-slate-200 bg-white p-2.5 text-sm text-slate-800 focus:outline-none dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"
          />
          <div className="mt-2 flex justify-end gap-2">
            <button onClick={cancel} className="rounded-lg px-3 py-1.5 text-sm text-slate-500 active:bg-slate-200 dark:text-slate-400 dark:active:bg-slate-700">Cancel</button>
            <button onClick={save} disabled={!draft.trim()} className="rounded-lg bg-sky-700 px-3 py-1.5 text-sm font-semibold text-white active:bg-sky-800 disabled:opacity-40 dark:bg-sky-600">
              {editingId ? "Save" : "Add Note"}
            </button>
          </div>
        </div>
      ) : (
        <button onClick={startAdd} className="w-full rounded-lg border border-dashed border-sky-300 py-2 text-sm font-medium text-sky-700 active:bg-sky-100 dark:border-sky-700 dark:text-sky-400 dark:active:bg-sky-900/40">
          + Add Note
        </button>
      )}
    </div>
  );
}

function AiContextModal({ node, onClose }) {
  const [entry] = useState(() => getAiContext(node.id));
  const [copiedApp, setCopiedApp] = useState(null);

  const handleAskExternal = async (app) => {
    const prompt = entry?.prompt?.trim() ||
      `Explain "${node.title || node.node_number}" (${node.node_type} ${node.node_number || ""}) from RA 10863, the Philippine Customs Modernization and Tariff Act, in simple terms with an example.`;
    await copyPromptAndOpen(prompt, app.url);
    setCopiedApp(app.id);
    setTimeout(() => setCopiedApp(null), 2500);
  };

  return (
    <div className="fixed inset-0 z-[70] flex items-end justify-center bg-slate-900/60 backdrop-blur-sm sm:items-center" onClick={onClose}>
      <div onClick={(e) => e.stopPropagation()} className="max-h-[88vh] w-full overflow-y-auto rounded-t-3xl bg-white p-5 shadow-2xl dark:bg-slate-900 sm:max-w-lg sm:rounded-3xl">
        <div className="mb-3 flex items-start justify-between gap-2">
          <div className="flex items-center gap-2">
            <span className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-amber-400 to-navy-700 text-lg">🤖</span>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">Osias 6.7</p>
              <p className="text-xl font-extrabold leading-tight text-slate-900 dark:text-slate-50">
                {entry?.title || `About ${node.node_type} ${node.node_number || ""}`}
              </p>
            </div>
          </div>
          <button onClick={onClose} className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-full text-slate-400 active:bg-slate-100 dark:text-slate-500 dark:active:bg-slate-800">✕</button>
        </div>

        {entry?.content ? (
          <p className="whitespace-pre-wrap rounded-2xl bg-slate-50 p-3 text-base leading-relaxed text-slate-700 dark:bg-slate-800/60 dark:text-slate-200">{entry.content}</p>
        ) : (
          <p className="rounded-2xl bg-slate-50 p-3 text-sm italic text-slate-400 dark:bg-slate-800/60 dark:text-slate-500">Osias 6.7 hasn't explained this part yet.</p>
        )}

        <div className="mt-4 border-t border-slate-100 pt-3 dark:border-slate-800">
          <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">Still confused? Ask another AI</p>
          <div className="flex flex-wrap gap-2">
            {AI_APPS.map((app) => (
              <button key={app.id} onClick={() => handleAskExternal(app)} className="flex min-h-[42px] items-center gap-1.5 rounded-full border border-slate-200 bg-white px-3.5 text-sm font-medium text-slate-700 active:bg-slate-100 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:active:bg-slate-700">
                <span aria-hidden>{app.icon}</span> {app.label}
              </button>
            ))}
          </div>
          {copiedApp && (
            <p className="mt-2 text-xs font-medium text-emerald-600 dark:text-emerald-400">
              ✓ Prompt copied — paste it in {AI_APPS.find((a) => a.id === copiedApp)?.label} and send.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
const STUDY_TYPE_STYLES = {
  chapter: "text-xl sm:text-2xl font-bold text-navy-900 dark:text-slate-50",
  section: "text-lg sm:text-xl font-semibold text-slate-800 dark:text-slate-200",
  paragraph: "text-base sm:text-lg text-slate-700 dark:text-slate-300",
  subparagraph: "text-base text-slate-600 dark:text-slate-400",
  item: "text-sm text-slate-500 dark:text-slate-500",
};

const STUDY_DEPTH_BORDERS = [
  "border-slate-200 dark:border-slate-700",
  "border-amber-200 dark:border-amber-800",
  "border-emerald-200 dark:border-emerald-800",
  "border-purple-200 dark:border-purple-800",
  "border-sky-200 dark:border-sky-800",
];

function StudyNodeRenderer({ node, level = 0, expandedSet = new Set(), scrollToId = null, collapseSignal = 0 }) {
  const nodeRef = useRef(null);
  const [expanded, setExpanded] = useState(false);
  const [notesOpen, setNotesOpen] = useState(false);
  const [aiModalOpen, setAiModalOpen] = useState(false);
  const aiEntry = useMemo(() => getAiContext(node.id), [node.id]);
  const { activeHighlightNodeId, setActiveHighlightNodeId } = useHighlightUI();
  const isHighlighting = activeHighlightNodeId === node.id;
  const hasChildren = node.children && node.children.length > 0;
  const isExpandable = hasChildren || !!node.content;
  const { highlights, addHighlight, removeHighlight } = useNodeHighlights(node.id, expanded);
  const { notes, createNote, editNote, removeNote } = useNodeNotes(node.id, true);
  const prevCollapseSignal = useRef(collapseSignal);
  
  useEffect(() => { if (expandedSet.has(node.id)) setExpanded(true); }, [expandedSet, node.id]);
  useEffect(() => {
    if (collapseSignal !== prevCollapseSignal.current) {
      prevCollapseSignal.current = collapseSignal;
      setExpanded(false);
    }
  }, [collapseSignal]);
  useEffect(() => {
    if (scrollToId === node.id && nodeRef.current) {
      setTimeout(() => {
        nodeRef.current.scrollIntoView({ behavior: "smooth", block: "center" });
        nodeRef.current.classList.add("ring-2", "ring-amber-400", "bg-amber-50", "dark:bg-amber-900/40");
        setTimeout(() => nodeRef.current?.classList.remove("ring-2", "ring-amber-400", "bg-amber-50", "dark:bg-amber-900/40"), 2200);
      }, 120);
    }
  }, [scrollToId, node.id]);

  const toggle = (e) => { e.stopPropagation(); if (isExpandable) setExpanded((v) => !v); };

  return (
    <div ref={nodeRef} style={{ marginLeft: `${Math.min(level, 6) * 0.9}rem` }} className="my-1 rounded-xl transition-colors">
      <div onClick={toggle} role="button" tabIndex={0} aria-expanded={isExpandable ? expanded : undefined} className="flex items-start gap-2 rounded-xl px-3 py-2.5 hover:bg-slate-50 active:bg-slate-100 cursor-pointer touch-manipulation dark:hover:bg-slate-800/60 dark:active:bg-slate-800">
        <span className={`mt-1 flex h-5 w-5 flex-shrink-0 items-center justify-center select-none text-slate-400 transition-transform duration-200 dark:text-slate-600 ${expanded ? "rotate-90" : ""}`}>{isExpandable ? "▸" : ""}</span>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            {node.node_type === "chapter" && <span className="inline-block rounded-md bg-navy-900 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide text-white dark:bg-navy-700">Chapter {node.node_number}</span>}
            {node.node_type === "section" && <span className="inline-block rounded-md bg-amber-100 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide text-amber-800 dark:bg-amber-900/40 dark:text-amber-300">Sec. {node.node_number}</span>}
            <span className={STUDY_TYPE_STYLES[node.node_type] || "text-sm text-slate-700 dark:text-slate-300"}>{node.title || node.node_number}</span>
            {!expanded && notes.length > 0 && <span className="text-xs" title="Has notes">📝</span>}
            {!expanded && aiEntry && <span className="text-xs" title="AI explanation available">🤖</span>}
          </div>
          {expanded && node.content && (
            <div onClick={(e) => e.stopPropagation()} className="mt-2">
              <HighlightableContent nodeId={node.id} content={node.content} highlights={highlights} addHighlight={addHighlight} removeHighlight={removeHighlight} armed={isHighlighting} className="select-text rounded-lg p-2 text-base leading-relaxed text-slate-700 dark:text-slate-300" />
              <div className="mt-1 flex flex-wrap items-center gap-2">
                <button onClick={() => setActiveHighlightNodeId(isHighlighting ? null : node.id)} className={`min-h-[38px] rounded-lg border px-3 py-1.5 text-sm font-medium transition-colors ${isHighlighting ? "border-amber-400 bg-amber-100 text-amber-800 dark:border-amber-600 dark:bg-amber-900/40 dark:text-amber-300" : "border-emerald-200 bg-emerald-50 text-emerald-700 active:bg-emerald-100 dark:border-emerald-700 dark:bg-emerald-950/30 dark:text-emerald-400 dark:active:bg-emerald-950/50"}`}>{isHighlighting ? "Select text to highlight…" : "🖍 Highlight"}</button>
                <button onClick={() => setNotesOpen((v) => !v)} className={`min-h-[38px] rounded-lg border px-3 py-1.5 text-sm font-medium transition-colors ${notesOpen ? "border-sky-400 bg-sky-100 text-sky-800 dark:border-sky-600 dark:bg-sky-900/40 dark:text-sky-300" : "border-sky-200 bg-sky-50 text-sky-700 active:bg-sky-100 dark:border-sky-700 dark:bg-sky-950/30 dark:text-sky-400 dark:active:bg-sky-950/50"}`}>
                  📝 {notes.length > 0 ? `Notes (${notes.length})` : "Add Note"}
                </button>
                <button onClick={() => setAiModalOpen(true)} className="min-h-[38px] rounded-lg border border-purple-200 bg-purple-50 px-3 py-1.5 text-sm font-medium text-purple-700 active:bg-purple-100 dark:border-purple-700 dark:bg-purple-950/30 dark:text-purple-400 dark:active:bg-purple-950/50">
                  🤖 Ask AI
                </button>
              </div>
              {notesOpen && (
                <NotePanel notes={notes} onCreate={createNote} onEdit={editNote} onDelete={removeNote} onClose={() => setNotesOpen(false)} />
              )}
              {aiModalOpen && <AiContextModal node={node} onClose={() => setAiModalOpen(false)} />}
              {node.cross_references && node.cross_references.length > 0 && (
                <div className="mt-3 rounded-lg bg-slate-50 p-3 text-sm dark:bg-slate-800/60" onClick={(e) => e.stopPropagation()}>
                  <span className="font-medium text-slate-700 dark:text-slate-300">See Also</span>
                  <ul className="mt-1 list-disc space-y-0.5 pl-4 text-slate-600 dark:text-slate-400">
                    {node.cross_references.map((ref, idx) => (
                      <li key={idx}>{ref.url ? <a href={ref.url} target="_blank" rel="noopener noreferrer" className="text-navy-700 underline decoration-navy-300 underline-offset-2 dark:text-amber-400 dark:decoration-amber-700">{ref.text}</a> : <span>{ref.text}</span>}</li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          )}
          {expanded && node.keywords?.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-1" onClick={(e) => e.stopPropagation()}>
              {node.keywords.map((kw) => <span key={kw} className="rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-500 dark:bg-slate-700 dark:text-slate-400">{kw}</span>)}
            </div>
          )}
        </div>
      </div>
      {expanded && hasChildren && (
        <div className={`ml-4 border-l-2 ${STUDY_DEPTH_BORDERS[(level + 1) % STUDY_DEPTH_BORDERS.length]}`}>
          {node.children.map((child) => <StudyNodeRenderer key={child.id} node={child} level={level + 1} expandedSet={expandedSet} scrollToId={scrollToId} collapseSignal={collapseSignal} />)}
        </div>
      )}
    </div>
  );
}

const READING_TYPE_STYLES = {
  chapter: "font-bold text-navy-900 dark:text-slate-50 mb-2",
  section: "font-semibold text-slate-900 dark:text-slate-100 mb-1",
  paragraph: "text-slate-800 dark:text-slate-300",
  subparagraph: "text-slate-800 dark:text-slate-300",
  item: "text-slate-700 dark:text-slate-400",
};

function ReadingNodeRenderer({ node, level = 0, fontScale, expandedSet = new Set(), scrollToId = null }) {
  const nodeRef = useRef(null);
  const [notesOpen, setNotesOpen] = useState(false);
  const [aiModalOpen, setAiModalOpen] = useState(false);
  const aiEntry = useMemo(() => getAiContext(node.id), [node.id]);
  const hasChildren = node.children && node.children.length > 0;
  const { highlights, addHighlight, removeHighlight } = useNodeHighlights(node.id, !!node.content);
  const { notes, createNote, editNote, removeNote } = useNodeNotes(node.id, true);
  
  useEffect(() => {
    if (scrollToId === node.id && nodeRef.current) {
      setTimeout(() => {
        nodeRef.current.scrollIntoView({ behavior: "smooth", block: "center" });
        nodeRef.current.classList.add("bg-amber-50", "dark:bg-amber-900/40");
        setTimeout(() => nodeRef.current?.classList.remove("bg-amber-50", "dark:bg-amber-900/40"), 2200);
      }, 120);
    }
  }, [scrollToId, node.id]);

  const headingSize = node.node_type === "chapter" ? 1.6 : node.node_type === "section" ? 1.3 : 1;
  return (
    <div ref={nodeRef} style={{ marginLeft: `${Math.min(level, 4) * 0.6}rem` }} className="my-5 rounded-lg transition-colors">
      <div className={`font-serif ${READING_TYPE_STYLES[node.node_type] || "text-slate-800 dark:text-slate-200"}`} style={{ fontSize: `${headingSize * fontScale}rem` }}>
        {node.node_type === "section" && `Section ${node.node_number}. `}
        {node.node_type === "chapter" && `Chapter ${node.node_number}. `}
        {node.title || node.node_number}
        {notes.length > 0 && <span className="ml-1 align-middle text-sm" title="Has notes">📝</span>}
        {aiEntry && <span className="ml-1 align-middle text-sm" title="AI explanation available">🤖</span>}
      </div>
      {node.content && <HighlightableContent nodeId={node.id} content={node.content} highlights={highlights} addHighlight={addHighlight} removeHighlight={removeHighlight} armed={true} className="select-text font-serif leading-loose text-slate-800 dark:text-slate-300" />}
      {node.content && (
        <div className="mt-2 flex flex-wrap items-center gap-2 font-sans">
          <button onClick={() => setNotesOpen((v) => !v)} className={`min-h-[36px] rounded-lg border px-3 py-1 text-sm font-medium transition-colors ${notesOpen ? "border-sky-400 bg-sky-100 text-sky-800 dark:border-sky-600 dark:bg-sky-900/40 dark:text-sky-300" : "border-sky-200 bg-sky-50 text-sky-700 active:bg-sky-100 dark:border-sky-700 dark:bg-sky-950/30 dark:text-sky-400 dark:active:bg-sky-950/50"}`}>
            📝 {notes.length > 0 ? `Notes (${notes.length})` : "Add Note"}
          </button>
          <button onClick={() => setAiModalOpen(true)} className="min-h-[36px] rounded-lg border border-purple-200 bg-purple-50 px-3 py-1 text-sm font-medium text-purple-700 active:bg-purple-100 dark:border-purple-700 dark:bg-purple-950/30 dark:text-purple-400 dark:active:bg-purple-950/50">
            🤖 Ask AI
          </button>
        </div>
      )}
      {notesOpen && (
        <div className="font-sans">
          <NotePanel notes={notes} onCreate={createNote} onEdit={editNote} onDelete={removeNote} onClose={() => setNotesOpen(false)} />
        </div>
      )}
      {aiModalOpen && <AiContextModal node={node} onClose={() => setAiModalOpen(false)} />}
      {node.cross_references && node.cross_references.length > 0 && (
        <div className="mt-2 rounded-lg bg-slate-50 p-3 font-sans text-sm dark:bg-slate-800/60">
          <span className="font-medium text-slate-700 dark:text-slate-300">See Also</span>
          <ul className="mt-1 list-disc space-y-0.5 pl-4 text-slate-600 dark:text-slate-400">
            {node.cross_references.map((ref, idx) => (
              <li key={idx}>{ref.url ? <a href={ref.url} target="_blank" rel="noopener noreferrer" className="text-navy-700 underline decoration-navy-300 underline-offset-2 dark:text-amber-400 dark:decoration-amber-700">{ref.text}</a> : <span>{ref.text}</span>}</li>
            ))}
          </ul>
        </div>
      )}
      {hasChildren && <div>{node.children.map((child) => <ReadingNodeRenderer key={child.id} node={child} level={level + 1} fontScale={fontScale} expandedSet={expandedSet} scrollToId={scrollToId} />)}</div>}
    </div>
  );
}

function ModeToggle({ mode, setMode }) {
  return (
    <div className="inline-flex flex-shrink-0 rounded-full bg-slate-100 p-1 text-sm dark:bg-slate-800" role="tablist" aria-label="View mode">
      <button role="tab" aria-selected={mode === "study"} onClick={() => setMode("study")} className={`min-h-[34px] rounded-full px-2.5 py-1 transition-colors ${mode === "study" ? "bg-navy-900 font-medium text-white shadow-sm dark:bg-navy-700" : "text-slate-500 dark:text-slate-400"}`}>
        <span aria-hidden>📘</span><span className="hidden sm:inline ml-1">Study</span>
      </button>
      <button role="tab" aria-selected={mode === "reading"} onClick={() => setMode("reading")} className={`min-h-[34px] rounded-full px-2.5 py-1 transition-colors ${mode === "reading" ? "bg-navy-900 font-medium text-white shadow-sm dark:bg-navy-700" : "text-slate-500 dark:text-slate-400"}`}>
        <span aria-hidden>📖</span><span className="hidden sm:inline ml-1">Reading</span>
      </button>
    </div>
  );
}

function FontStepper({ fontScale, setFontScale }) {
  const clamp = (v) => Math.min(1.6, Math.max(0.85, v));
  return (
    <div className="flex items-center gap-1.5 text-sm">
      <button onClick={() => setFontScale((s) => clamp(s - 0.1))} className="flex h-9 w-9 items-center justify-center rounded-full border border-slate-200 text-slate-600 active:bg-slate-100 dark:border-slate-600 dark:text-slate-300 dark:active:bg-slate-700" aria-label="Decrease font size">A-</button>
      <span className="w-10 text-center text-xs text-slate-400 dark:text-slate-500">{Math.round(fontScale * 100)}%</span>
      <button onClick={() => setFontScale((s) => clamp(s + 0.1))} className="flex h-9 w-9 items-center justify-center rounded-full border border-slate-200 text-slate-600 active:bg-slate-100 dark:border-slate-600 dark:text-slate-300 dark:active:bg-slate-700" aria-label="Increase font size">A+</button>
    </div>
  );
}

function ReadingProgressBar({ containerRef }) {
  const [pct, setPct] = useState(0);
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const onScroll = () => { const max = el.scrollHeight - el.clientHeight; setPct(max > 0 ? Math.min(100, (el.scrollTop / max) * 100) : 0); };
    el.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    return () => el.removeEventListener("scroll", onScroll);
  }, [containerRef]);
  return (
    <div className="h-1 w-full bg-slate-100 dark:bg-slate-800">
      <div className="h-1 bg-gradient-to-r from-amber-400 to-navy-700 transition-all dark:from-amber-500 dark:to-navy-400" style={{ width: `${pct}%` }} />
    </div>
  );
}

function FilterChip({ label, value, active, onClick }) {
  return (
    <button onClick={() => onClick(value)} className={`min-h-[38px] rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors ${active ? "border-navy-900 bg-navy-900 text-white dark:border-navy-600 dark:bg-navy-700" : "border-slate-200 bg-white text-slate-600 active:bg-slate-100 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300 dark:active:bg-slate-700"}`}>{label}</button>
  );
}

function SearchResultCard({ item, onClick }) {
  const buildPath = () => {
    const parts = [];
    if (item.title_number) parts.push(`TITLE ${item.title_number}`);
    if (item.chapter_number) parts.push(`Ch. ${item.chapter_number}`);
    if (item.node_type === "section") parts.push(`Sec. ${item.node_number}`);
    return parts.join(" · ") || item.node_type.toUpperCase();
  };
  const typeColors = {
    title: "bg-purple-100 text-purple-700 dark:bg-purple-900/40 dark:text-purple-300",
    chapter: "bg-navy-900 text-white dark:bg-navy-700",
    section: "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300",
    paragraph: "bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300",
    subparagraph: "bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300",
    item: "bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300",
  };
  return (
    <button onClick={onClick} className={`block w-full rounded-2xl border bg-white p-4 text-left shadow-card transition active:scale-[0.99] active:bg-slate-50 dark:bg-slate-800 dark:active:bg-slate-700/70 ${item.exact_match ? "border-amber-400 ring-1 ring-amber-300 dark:border-amber-600 dark:ring-amber-700" : "border-slate-200 dark:border-slate-700"}`}>
      <div className="flex items-center justify-between gap-2">
        <div className="flex flex-wrap items-center gap-1.5 text-xs">
          <span className={`rounded-md px-1.5 py-0.5 font-semibold uppercase tracking-wide ${typeColors[item.node_type] || "bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300"}`}>{item.node_type}</span>
          <span className="text-slate-400 dark:text-slate-500">{buildPath()}</span>
        </div>
        {item.exact_match && <span className="flex-shrink-0 rounded-full bg-amber-400 px-2 py-0.5 text-xs font-semibold text-amber-950 dark:bg-amber-500 dark:text-amber-950">✓ Exact match</span>}
      </div>
      <div className="mt-1.5 text-base font-semibold text-slate-900 dark:text-slate-100">{item.title || item.node_number}</div>
      {item.excerpt && <div className="mt-1 text-sm leading-relaxed text-slate-500 dark:text-slate-400" dangerouslySetInnerHTML={{ __html: item.excerpt.replace(/\[/g, "<mark>").replace(/\]/g, "</mark>") }} />}
      <div className="mt-2 flex items-center gap-1 text-xs font-medium text-navy-700 dark:text-amber-400">Open <span aria-hidden>→</span></div>
    </button>
  );
}

function SearchView({ onNavigateChapter }) {
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("all");
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [hasSearched, setHasSearched] = useState(false);
  const inputRef = useRef(null);
  
  const handleSearch = useCallback(async () => {
    if (!query.trim()) return;
    setLoading(true); setError(null); setHasSearched(true);
    try {
      const data = await search(query.trim(), filter);
      setResults(data);
    } catch (err) {
      setError(err.message);
      setResults([]);
    } finally { setLoading(false); }
  }, [query, filter]);

  const handleKeyDown = (e) => { if (e.key === "Enter") handleSearch(); };
  const clearQuery = () => { setQuery(""); setResults([]); setHasSearched(false); inputRef.current?.focus(); };
  
  const handleResultClick = async (item) => {
    if (item.chapter_number) {
      onNavigateChapter(item.chapter_number, item.title_number, item.node_id);
    } else {
      try {
        const chapterInfo = await getChapterForNode(item.node_id);
        if (chapterInfo) {
          onNavigateChapter(chapterInfo.chapter_number, chapterInfo.title_number, item.node_id);
        } else {
          alert('This item is not under any chapter. Please browse manually.');
        }
      } catch (e) {
        alert('Could not locate the chapter for this item.');
        console.error(e);
      }
    }
  };
  
  const exactResults = results.filter((r) => r.exact_match);
  const otherResults = results.filter((r) => !r.exact_match);
  
  return (
    <div className="mx-auto max-w-3xl p-4">
      <div className="rounded-2xl border border-slate-200 bg-white p-3 shadow-card dark:border-slate-700 dark:bg-slate-800">
        <div className="flex items-center gap-2">
          <span className="pl-1 text-lg text-slate-400 dark:text-slate-500" aria-hidden>🔍</span>
          <input ref={inputRef} type="text" value={query} onChange={(e) => setQuery(e.target.value)} onKeyDown={handleKeyDown} placeholder='Search e.g. "Section 102" or "smuggling"' className="min-w-0 flex-1 border-none bg-transparent py-2 text-base text-slate-900 placeholder:text-slate-400 focus:outline-none dark:text-slate-100 dark:placeholder:text-slate-500" style={{ fontSize: "16px" }} />
          {query && <button onClick={clearQuery} className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full text-slate-400 active:bg-slate-100 dark:text-slate-500 dark:active:bg-slate-700" aria-label="Clear search">✕</button>}
        </div>
        <div className="mt-2 flex flex-wrap items-center justify-between gap-2 border-t border-slate-100 pt-2 dark:border-slate-700">
          <div className="flex flex-wrap gap-1.5">
            <FilterChip label="All" value="all" active={filter === "all"} onClick={setFilter} />
            <FilterChip label="Title" value="title" active={filter === "title"} onClick={setFilter} />
            <FilterChip label="Chapter" value="chapter" active={filter === "chapter"} onClick={setFilter} />
            <FilterChip label="Section" value="section" active={filter === "section"} onClick={setFilter} />
          </div>
          <button onClick={handleSearch} disabled={loading || !query.trim()} className="min-h-[38px] flex-shrink-0 rounded-full bg-navy-900 px-5 py-1.5 text-sm font-semibold text-white shadow-sm active:bg-navy-800 disabled:opacity-40 dark:bg-navy-700 dark:active:bg-navy-600">{loading ? "Searching…" : "Search"}</button>
        </div>
      </div>
      {error && <p className="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-600 dark:bg-red-950/30 dark:text-red-400">{error}</p>}
      {loading && (
        <div className="mt-4 space-y-3">
          {[0,1,2].map(i => <div key={i} className="animate-pulse rounded-2xl border border-slate-200 bg-white p-4 dark:border-slate-700 dark:bg-slate-800"><div className="h-3 w-1/3 rounded bg-slate-200 dark:bg-slate-700"/><div className="mt-3 h-4 w-2/3 rounded bg-slate-200 dark:bg-slate-700"/><div className="mt-2 h-3 w-full rounded bg-slate-100 dark:bg-slate-700/60"/></div>)}
        </div>
      )}
      {!loading && exactResults.length > 0 && <div className="mt-5 space-y-2">{exactResults.map((item, idx) => <SearchResultCard key={`exact-${idx}`} item={item} onClick={() => handleResultClick(item)} />)}</div>}
      {!loading && otherResults.length > 0 && <div className="mt-5">{exactResults.length > 0 && <p className="mb-2 px-1 text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">Related mentions</p>}<div className="space-y-2">{otherResults.map((item, idx) => <SearchResultCard key={`other-${idx}`} item={item} onClick={() => handleResultClick(item)} />)}</div></div>}
      {!loading && hasSearched && results.length === 0 && !error && <div className="mt-10 flex flex-col items-center gap-2 text-center text-slate-400 dark:text-slate-600"><span className="text-3xl">🔎</span><p className="text-base font-medium text-slate-500 dark:text-slate-400">No results for "{query}"</p><p className="text-sm">Try a section number (e.g. 102), a keyword, or a shorter phrase.</p></div>}
      {!hasSearched && !loading && <div className="mt-10 flex flex-col items-center gap-2 text-center text-slate-400 dark:text-slate-600"><span className="text-3xl">📚</span><p className="text-sm">Search the full text of RA 10863 — titles, chapters, sections, and definitions.</p></div>}
    </div>
  );
}

function DarkModeToggle({ enabled, onChange }) {
  return (
    <button type="button" role="switch" aria-checked={enabled} onClick={() => onChange(!enabled)} className={`relative inline-flex h-8 w-14 flex-shrink-0 items-center rounded-full transition-colors duration-300 ${enabled ? "bg-navy-700" : "bg-slate-300"}`}>
      <span className={`inline-block h-6 w-6 transform rounded-full bg-white shadow-md transition-transform duration-300 ${enabled ? "translate-x-7" : "translate-x-1"}`} />
    </button>
  );
}

const TUTORIAL_STEPS = [
  { icon: "⚖️", title: "Welcome to RA 10863", body: "Your complete offline companion for the Customs Modernization and Tariff Act. Let's take a 60-second tour of what you can do." },
  { icon: "📚", title: "Browse the Law", body: "Tap the menu button (☰) to open the sidebar. Every Title, Chapter, and Section is organized in the correct legal order." },
  { icon: "📘", title: "Study Mode", body: "Expand one section at a time to focus on details. Use Expand All or Collapse All at the top to move through a whole chapter faster." },
  { icon: "📖", title: "Reading Mode", body: "A clean, book-style view for long reading sessions. Tap 🎯 Focus to hide the toolbar and read distraction-free." },
  { icon: "🖍️", title: "Highlights", body: "Select any text to highlight it. Works in both Study and Reading mode, and is saved automatically — even offline." },
  { icon: "📝", title: "Notes", body: "Tap \"Add Note\" under any section to write your own explanation. Edit or delete your notes anytime." },
  { icon: "🤖", title: "Ask AI", body: "Tap Ask AI under any section for an instant offline explanation from Osias 6.7 — or hand off to Meta AI, ChatGPT, or Gemini with one tap." },
  { icon: "🔍", title: "Search", body: "Find anything instantly. Try a section number like \"102\", or a keyword like \"smuggling\"." },
  { icon: "⏱️", title: "Resume Reading", body: "Close the app anytime — a \"Continue where you left off\" card will bring you right back to your spot." },
  { icon: "⚙️", title: "Settings", body: "Switch Dark Mode on or off, and replay this tour anytime from the Settings screen." },
];

function TutorialOverlay({ onFinish }) {
  const [step, setStep] = useState(0);
  const total = TUTORIAL_STEPS.length;
  const isLast = step === total - 1;
  const current = TUTORIAL_STEPS[step];

  const next = () => { if (isLast) onFinish(); else setStep((s) => s + 1); };
  const back = () => setStep((s) => Math.max(0, s - 1));

  return (
    <div className="fixed inset-0 z-[60] flex flex-col justify-end bg-slate-900/70 backdrop-blur-sm sm:items-center sm:justify-center">
      <div className="w-full rounded-t-3xl bg-white p-6 shadow-2xl dark:bg-slate-900 sm:max-w-md sm:rounded-3xl">
        <div className="mb-4 flex items-center justify-between">
          <div className="flex gap-1.5">
            {TUTORIAL_STEPS.map((_, i) => (
              <span key={i} className={`h-1.5 rounded-full transition-all duration-300 ${i === step ? "w-6 bg-navy-900 dark:bg-slate-100" : "w-1.5 bg-slate-200 dark:bg-slate-700"}`} />
            ))}
          </div>
          <button onClick={onFinish} className="text-sm font-medium text-slate-400 active:text-slate-600 dark:text-slate-500 dark:active:text-slate-300">
            Skip
          </button>
        </div>
        <div className="mb-6 flex flex-col items-center text-center">
          <span className="mb-3 text-5xl" aria-hidden>{current.icon}</span>
          <h2 className="mb-2 text-xl font-bold text-slate-900 dark:text-slate-50">{current.title}</h2>
          <p className="text-sm leading-relaxed text-slate-600 dark:text-slate-300">{current.body}</p>
        </div>
        <div className="flex items-center gap-2">
          {step > 0 && (
            <button onClick={back} className="flex h-12 flex-1 items-center justify-center rounded-xl border border-slate-200 text-sm font-semibold text-slate-600 active:bg-slate-100 dark:border-slate-600 dark:text-slate-300 dark:active:bg-slate-800">
              Back
            </button>
          )}
          <button onClick={next} className="flex h-12 flex-[2] items-center justify-center rounded-xl bg-navy-900 text-sm font-semibold text-white shadow-sm active:bg-navy-800 dark:bg-navy-700 dark:active:bg-navy-600">
            {isLast ? "Start Exploring" : "Next"}
          </button>
        </div>
      </div>
    </div>
  );
}

function SettingsView({ darkMode, setDarkMode, onReplayTutorial }) {
  return (
    <div className="mx-auto max-w-2xl pb-10">
      <h1 className="mb-1 text-2xl font-bold text-slate-900 dark:text-slate-50">Settings</h1>
      <p className="mb-6 text-sm text-slate-500 dark:text-slate-400">Customize your reading experience.</p>
      <section className="mb-6 rounded-2xl border border-slate-200 bg-white p-4 shadow-card dark:border-slate-700 dark:bg-slate-800">
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">Appearance</h2>
        <div className="flex items-center justify-between gap-4 rounded-xl py-1">
          <div className="min-w-0"><p className="font-medium text-slate-800 dark:text-slate-100">🌙 Dark Mode</p><p className="text-sm text-slate-500 dark:text-slate-400">Easier on the eyes in low light.</p></div>
          <DarkModeToggle enabled={darkMode} onChange={setDarkMode} />
        </div>
      </section>
      <section className="mb-6 rounded-2xl border border-slate-200 bg-white p-4 shadow-card dark:border-slate-700 dark:bg-slate-800">
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">Help</h2>
        <button onClick={onReplayTutorial} className="flex min-h-[44px] w-full items-center justify-center gap-2 rounded-xl border border-slate-200 px-4 py-2.5 text-sm font-semibold text-slate-700 active:bg-slate-100 dark:border-slate-600 dark:text-slate-200 dark:active:bg-slate-700">
          🔄 Replay Tutorial
        </button>
      </section>
      <section className="mb-6 rounded-2xl border border-slate-200 bg-white p-4 shadow-card dark:border-slate-700 dark:bg-slate-800">
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">About this App</h2>
        <p className="text-sm leading-relaxed text-slate-600 dark:text-slate-300">RA 10863 — Customs Modernization and Tariff Act. A study &amp; reading companion with search and highlights. Works fully offline.</p>
        <p className="mt-2 text-xs text-slate-400 dark:text-slate-500">Version 1.0.0 (Offline)</p>
      </section>
      <section className="rounded-2xl border border-slate-200 bg-white p-4 shadow-card dark:border-slate-700 dark:bg-slate-800">
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">Developer</h2>
        <div className="flex items-center gap-3">
          <div className="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-navy-900 text-lg font-bold text-white dark:bg-navy-700">O</div>
          <div className="min-w-0"><p className="font-semibold text-slate-800 dark:text-slate-100">Osias</p><p className="text-sm text-slate-500 dark:text-slate-400">App developer &amp; maintainer</p></div>
        </div>
        <a href="https://osiasnalaunan68-star.github.io/osias-personal-portfolio" target="_blank" rel="noopener noreferrer" className="mt-4 flex min-h-[44px] items-center justify-center gap-2 rounded-xl bg-navy-900 px-4 py-2.5 text-sm font-semibold text-white shadow-sm active:bg-navy-800 dark:bg-navy-700 dark:active:bg-navy-600">🌐 View Developer Portfolio</a>
      </section>
    </div>
  );
}

function findNodeByIdAndAncestors(node, targetId, ancestors = []) {
  if (node.id === targetId) return { found: true, ancestors, node };
  if (node.children) {
    for (const child of node.children) {
      const result = findNodeByIdAndAncestors(child, targetId, [...ancestors, node.id]);
      if (result.found) return result;
    }
  }
  return { found: false };
}

function collectAllNodeIds(node, acc = []) {
  if (node.children && node.children.length > 0) {
    acc.push(node.id);
    for (const child of node.children) collectAllNodeIds(child, acc);
  } else if (node.content) {
    acc.push(node.id);
  }
  return acc;
}

export default function ChapterBrowser() {
  const [view, setView] = useState("browse");
  const [titles, setTitles] = useState([]);
  const [selectedChapter, setSelectedChapter] = useState(null);
  const [selectedTitleNumber, setSelectedTitleNumber] = useState(null);
  const [chapterTree, setChapterTree] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [sidebarOpen, setSidebarOpen] = useState(() => window.innerWidth >= 768);
  const [mode, setMode] = useState(() => localStorage.getItem(MODE_KEY) || "study");
  const [fontScale, setFontScale] = useState(() => { const saved = parseFloat(localStorage.getItem(FONT_KEY)); return isNaN(saved) ? 1 : saved; });
  const [darkMode, setDarkMode] = useState(() => localStorage.getItem(DARK_KEY) === "true");
  const [activeHighlightNodeId, setActiveHighlightNodeId] = useState(null);
  const [expandedNodeIds, setExpandedNodeIds] = useState(new Set());
  const [scrollToNodeId, setScrollToNodeId] = useState(null);
  const [collapsedTitles, setCollapsedTitles] = useState({});
  const [studyCollapseSignal, setStudyCollapseSignal] = useState(0);
  const [focusMode, setFocusMode] = useState(false);
  const [resumeAvailable, setResumeAvailable] = useState(null);
  const [showTutorial, setShowTutorial] = useState(false);
  const mainRef = useRef(null);
  const pendingScrollRestore = useRef(null);
  const scrollSaveTimeout = useRef(null);

  useEffect(() => localStorage.setItem(MODE_KEY, mode), [mode]);
  useEffect(() => localStorage.setItem(FONT_KEY, String(fontScale)), [fontScale]);
  useEffect(() => {
    localStorage.setItem(DARK_KEY, String(darkMode));
    document.documentElement.classList.toggle("dark", darkMode);
  }, [darkMode]);

  useEffect(() => {
    getTitles()
      .then(setTitles)
      .catch((err) => {
        console.error("Failed to load titles:", err);
        setError(err.message);
      });
    const progress = getProgress();
    if (progress && progress.chapter_number) setResumeAvailable(progress);
    if (!hasTutorialBeenSeen()) {
      setShowTutorial(true);
    }
  }, []);

  const finishTutorial = useCallback(() => {
    markTutorialSeen();
    setShowTutorial(false);
  }, []);

  const replayTutorial = useCallback(() => {
    setShowTutorial(true);
  }, []);

  const loadChapter = useCallback(async (chapterNumber, titleNumber = null, targetNodeId = null) => {
    setLoading(true); setError(null);
    try {
      const data = await getChapter(chapterNumber, titleNumber);
      if (!data) throw new Error("Chapter not found");
      setChapterTree(data);
      setSelectedChapter(chapterNumber);
      setSelectedTitleNumber(titleNumber);
      setView("browse");
      setSidebarOpen(window.innerWidth >= 768);
      if (targetNodeId && data) {
        const { found, ancestors, node: foundNode } = findNodeByIdAndAncestors(data, targetNodeId);
        if (found) {
          setExpandedNodeIds(new Set([...ancestors, foundNode.id]));
          setScrollToNodeId(foundNode.id);
        } else {
          setExpandedNodeIds(new Set());
          setScrollToNodeId(null);
        }
      } else {
        setExpandedNodeIds(new Set());
        setScrollToNodeId(null);
      }
      if (pendingScrollRestore.current != null) {
        const targetScroll = pendingScrollRestore.current;
        pendingScrollRestore.current = null;
        setTimeout(() => { if (mainRef.current) mainRef.current.scrollTop = targetScroll; }, 180);
      } else if (mainRef.current) {
        mainRef.current.scrollTop = 0;
      }
    } catch (err) {
      setError(err.message);
      setChapterTree(null);
    } finally {
      setLoading(false);
    }
  }, []);

  const resumeReading = useCallback(() => {
    if (!resumeAvailable) return;
    if (resumeAvailable.mode) setMode(resumeAvailable.mode);
    pendingScrollRestore.current = resumeAvailable.scrollTop || 0;
    loadChapter(resumeAvailable.chapter_number, resumeAvailable.title_number || null);
  }, [resumeAvailable, loadChapter]);

  useEffect(() => {
    if (!chapterTree || view !== "browse") return;
    const el = mainRef.current;
    if (!el) return;
    const persist = () => {
      saveProgress({
        title_number: selectedTitleNumber,
        chapter_number: selectedChapter,
        mode,
        scrollTop: el.scrollTop,
      });
    };
    const onScroll = () => {
      if (scrollSaveTimeout.current) clearTimeout(scrollSaveTimeout.current);
      scrollSaveTimeout.current = setTimeout(persist, 500);
    };
    persist();
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      el.removeEventListener("scroll", onScroll);
      if (scrollSaveTimeout.current) clearTimeout(scrollSaveTimeout.current);
    };
  }, [chapterTree, selectedChapter, selectedTitleNumber, mode, view]);

  const toggleTitleCollapse = (key) => { setCollapsedTitles(prev => ({ ...prev, [key]: !prev[key] })); };
  
  const expandAllStudy = () => {
    if (!chapterTree) return;
    const ids = [];
    for (const section of chapterTree.children) collectAllNodeIds(section, ids);
    setExpandedNodeIds(new Set(ids));
  };
  
  const collapseAllStudy = () => {
    setExpandedNodeIds(new Set());
    setStudyCollapseSignal((v) => v + 1);
  };

  // 🔽 BINAGO: i-download bilang .txt file sa halip na clipboard, at nakatago sa IS_DEV
  const handleCopyQuizTemplate = useCallback(async (titleNumber) => {
    try {
      const tree = await getTitleTree(titleNumber);
      if (!tree) { alert("Could not load this title."); return; }
      const payload = copyQuizPromptForTitle(tree);
      const blob = new Blob([payload], { type: 'text/plain;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `quiz-prompt-Title-${titleNumber}.txt`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);
      alert(`✅ Na-download ang quiz-generation prompt para sa Title ${titleNumber} bilang .txt file.

📝 INSTRUCTIONS FOR AI:
1. Act like a professor designing a CuBLE exam.
2. SELECTIVELY choose the most important and testable provisions.
3. There is NO fixed number of questions — generate as many as educationally appropriate.
4. Use web search (if available) to verify CuBLE exam patterns and frequently tested topics.
5. Focus on QUALITY over QUANTITY — board-exam relevant questions only.

⚠️ IMPORTANT: The AI will SKIP minor, procedural, or repetitive provisions.`);
    } catch (err) {
      alert("Failed to build quiz template: " + err.message);
    }
  }, []);

  const highlightUIValue = useMemo(() => ({ activeHighlightNodeId, setActiveHighlightNodeId }), [activeHighlightNodeId]);

  return (
    <HighlightUIContext.Provider value={highlightUIValue}>
      <div className="relative flex h-screen overflow-hidden bg-slate-50 dark:bg-slate-950" style={{ height: "100dvh" }}>
        {sidebarOpen && view === "browse" && <div className="fixed inset-0 z-30 bg-slate-900/40 backdrop-blur-[1px] md:hidden" onClick={() => setSidebarOpen(false)} />}
        {view === "browse" && (
          <aside className={`safe-top fixed inset-y-0 left-0 z-40 w-[85vw] max-w-[320px] overflow-y-auto overscroll-contain border-r border-slate-200 bg-white transition-transform duration-200 dark:border-slate-800 dark:bg-slate-900 md:static md:w-80 md:max-w-none md:translate-x-0 ${sidebarOpen ? "translate-x-0" : "-translate-x-full"}`}>
            <div className="sticky top-0 z-10 border-b border-slate-100 bg-white/95 px-5 py-4 backdrop-blur dark:border-slate-800 dark:bg-slate-900/95">
              <div className="flex items-center gap-2"><span className="text-xl" aria-hidden>⚖️</span><div><h2 className="text-base font-bold leading-tight text-navy-900 dark:text-slate-50">RA 10863</h2><p className="text-xs text-slate-400 dark:text-slate-500">Customs Modernization &amp; Tariff Act</p></div></div>
            </div>
            <div className="p-3">
              {error && <p className="mb-2 rounded-lg bg-red-50 p-2 text-sm text-red-600 dark:bg-red-950/30 dark:text-red-400">{error}</p>}
              {titles.map((titleGroup) => {
                const key = titleGroup.title_number || "root";
                const collapsed = collapsedTitles[key];
                return (
                  <div key={key} className="mb-2">
                    <div className="flex items-center gap-1">
                      <button onClick={() => toggleTitleCollapse(key)} className="flex min-h-[40px] flex-1 items-center justify-between gap-2 rounded-lg px-2 py-2 text-left active:bg-slate-50 dark:active:bg-slate-800">
                        <span className="text-sm font-bold uppercase tracking-wide text-navy-800 dark:text-slate-300">{titleGroup.title_number ? `Title ${titleGroup.title_number}` : titleGroup.title_title}</span>
                        <span className="flex-shrink-0 text-xs text-slate-400 dark:text-slate-500">{collapsed ? "▸" : "▾"}</span>
                      </button>
                      {IS_DEV && titleGroup.title_number && (
                        <button
                          onClick={() => handleCopyQuizTemplate(titleGroup.title_number)}
                          title="Download Quiz Template as .txt"
                          className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-lg border border-dashed border-purple-400 text-sm text-purple-700 active:bg-purple-100 dark:border-purple-600 dark:text-purple-400"
                        >
                          📝
                        </button>
                      )}
                    </div>
                    {!collapsed && (
                      <ul className="ml-1 space-y-0.5 border-l border-slate-100 pl-2 dark:border-slate-800">
                        {titleGroup.chapters.map((ch) => {
                          const active = selectedChapter === ch.node_number && selectedTitleNumber === titleGroup.title_number;
                          return (
                            <li key={ch.id}>
                              <button onClick={() => loadChapter(ch.node_number, titleGroup.title_number)} className={`block min-h-[44px] w-full rounded-lg px-3 py-2 text-left text-sm transition-colors ${active ? "bg-navy-900 font-medium text-white shadow-sm dark:bg-navy-700" : "text-slate-600 active:bg-slate-100 dark:text-slate-400 dark:active:bg-slate-800"}`}>
                                <span className="block truncate">Ch. {ch.node_number}: {ch.title}</span>
                                <span className={`text-xs ${active ? "text-slate-300" : "text-slate-400 dark:text-slate-500"}`}>{ch.section_count} section{ch.section_count !== 1 ? "s" : ""}</span>
                              </button>
                            </li>
                          );
                        })}
                      </ul>
                    )}
                  </div>
                );
              })}
            </div>
          </aside>
        )}
        <div className="flex min-w-0 flex-1 flex-col">
          <div className="safe-top sticky top-0 z-20 border-b border-slate-200 bg-white/90 backdrop-blur dark:border-slate-800 dark:bg-slate-900/90">
            <div className={`flex items-center gap-1.5 px-2 transition-all duration-300 ${focusMode && mode === "reading" ? "max-h-0 overflow-hidden opacity-0 py-0" : "max-h-16 py-2 opacity-100"}`}>
              {view === "browse" && (
                <button onClick={() => setSidebarOpen((v) => !v)} className="flex h-9 w-9 flex-shrink-0 touch-manipulation items-center justify-center rounded-full text-lg text-slate-600 active:bg-slate-100 dark:text-slate-300 dark:active:bg-slate-800" aria-label="Toggle chapter list">
                  {sidebarOpen ? "✕" : "☰"}
                </button>
              )}
              <div className="flex flex-shrink-0 rounded-full bg-slate-100 p-1 text-sm dark:bg-slate-800">
                <button onClick={() => setView("browse")} aria-label="Browse" className={`min-h-[34px] rounded-full px-2.5 py-1 font-medium transition-colors ${view === "browse" ? "bg-white text-navy-900 shadow-sm dark:bg-slate-700 dark:text-slate-50" : "text-slate-500 dark:text-slate-400"}`}>
                  <span aria-hidden>📚</span><span className="hidden sm:inline ml-1">Browse</span>
                </button>
                <button onClick={() => setView("search")} aria-label="Search" className={`min-h-[34px] rounded-full px-2.5 py-1 font-medium transition-colors ${view === "search" ? "bg-white text-navy-900 shadow-sm dark:bg-slate-700 dark:text-slate-50" : "text-slate-500 dark:text-slate-400"}`}>
                  <span aria-hidden>🔍</span><span className="hidden sm:inline ml-1">Search</span>
                </button>
                <button onClick={() => setView("quiz")} aria-label="Quiz/Exam" className={`min-h-[34px] rounded-full px-2.5 py-1 font-medium transition-colors ${view === "quiz" ? "bg-white text-navy-900 shadow-sm dark:bg-slate-700 dark:text-slate-50" : "text-slate-500 dark:text-slate-400"}`}>
                  <span aria-hidden>📝</span><span className="hidden sm:inline ml-1">Quiz/Exam</span>
                </button>
                <button onClick={() => setView("settings")} aria-label="Settings" className={`min-h-[34px] rounded-full px-2.5 py-1 font-medium transition-colors ${view === "settings" ? "bg-white text-navy-900 shadow-sm dark:bg-slate-700 dark:text-slate-50" : "text-slate-500 dark:text-slate-400"}`}>
                  ⚙️
                </button>
                {IS_DEV && (
                  <button onClick={() => setView("dev")} aria-label="Dev Panel" className={`min-h-[34px] rounded-full px-2.5 py-1 font-medium transition-colors ${view === "dev" ? "bg-white text-navy-900 shadow-sm dark:bg-slate-700 dark:text-slate-50" : "text-slate-500 dark:text-slate-400"}`}>
                    🛠
                  </button>
                )}
              </div>
              <span className="flex-1" />
              {view === "browse" && <ModeToggle mode={mode} setMode={setMode} />}
            </div>
            {view === "browse" && !(focusMode && mode === "reading") && (
              <div className="px-3 pb-2">
                <span className="block truncate text-sm font-semibold text-slate-800 dark:text-slate-200">
                  {chapterTree ? chapterTree.title || `Chapter ${chapterTree.node_number}` : "Select a chapter"}
                </span>
              </div>
            )}
            {view === "browse" && mode === "reading" && (
              <div className="flex items-center justify-end gap-2 px-3 pb-2">
                <button onClick={() => setFocusMode((v) => !v)} className={`flex h-9 items-center gap-1 rounded-full border px-3 text-sm font-medium transition-colors ${focusMode ? "border-navy-900 bg-navy-900 text-white dark:border-slate-200 dark:bg-slate-100 dark:text-navy-900" : "border-slate-200 text-slate-600 active:bg-slate-100 dark:border-slate-600 dark:text-slate-300 dark:active:bg-slate-700"}`}>
                  🎯 <span className="hidden sm:inline">Focus</span>
                </button>
                <FontStepper fontScale={fontScale} setFontScale={setFontScale} />
              </div>
            )}
            {view === "browse" && mode === "reading" && chapterTree && <ReadingProgressBar containerRef={mainRef} />}
          </div>
          <main ref={mainRef} className="safe-bottom flex-1 overflow-y-auto overscroll-contain bg-slate-50 p-4 dark:bg-slate-950 md:p-6">
            {error && (
              <div className="mx-auto max-w-3xl rounded-xl border border-red-200 bg-red-50 p-4 text-red-800 dark:border-red-800 dark:bg-red-950/30 dark:text-red-200">
                <p className="font-bold">⚠️ Error</p>
                <p className="text-sm">{error}</p>
              </div>
            )}
            {view === "search" ? <SearchView onNavigateChapter={loadChapter} /> : view === "dev" && IS_DEV ? <DevPanel /> : view === "quiz" ? <QuizPage /> : view === "settings" ? <SettingsView darkMode={darkMode} setDarkMode={setDarkMode} onReplayTutorial={replayTutorial} /> : (
              <>
                {loading && (
                  <div className="mx-auto max-w-3xl space-y-3">
                    {[0,1,2].map(i => <div key={i} className="animate-pulse rounded-2xl border border-slate-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-900"><div className="h-4 w-1/2 rounded bg-slate-200 dark:bg-slate-700"/><div className="mt-3 h-3 w-full rounded bg-slate-100 dark:bg-slate-800"/><div className="mt-2 h-3 w-5/6 rounded bg-slate-100 dark:bg-slate-800"/></div>)}
                  </div>
                )}
                {!loading && !chapterTree && !error && (
                  <div className="flex h-full flex-col items-center justify-center gap-3 px-6 text-center text-slate-400 dark:text-slate-600">
                    {resumeAvailable && (
                      <button onClick={resumeReading} className="mb-2 flex w-full max-w-sm items-center gap-3 rounded-2xl border border-navy-200 bg-white p-4 text-left shadow-card active:bg-slate-50 dark:border-navy-700 dark:bg-slate-900 dark:active:bg-slate-800">
                        <span className="text-2xl" aria-hidden>⏱️</span>
                        <span className="min-w-0">
                          <span className="block text-sm font-semibold text-navy-900 dark:text-slate-100">Continue where you left off</span>
                          <span className="block truncate text-xs text-slate-500 dark:text-slate-400">
                            {resumeAvailable.title_number ? `Title ${resumeAvailable.title_number} · ` : ""}Chapter {resumeAvailable.chapter_number}
                          </span>
                        </span>
                      </button>
                    )}
                    <span className="text-4xl">📖</span>
                    <p className="text-lg font-medium text-slate-500 dark:text-slate-400">Select a chapter to start {mode === "reading" ? "reading" : "studying"}</p>
                    <p className="text-sm">Use the menu button or Search to find what you need.</p>
                  </div>
                )}
                {chapterTree && mode === "study" && (
                  <div className="mx-auto max-w-3xl">
                    {chapterTree.content && <p className="mb-4 rounded-xl bg-white p-4 text-base text-slate-600 shadow-card dark:bg-slate-900 dark:text-slate-300">{chapterTree.content}</p>}
                    <div className="mb-3 flex flex-wrap items-center justify-end gap-2">
                      <button onClick={expandAllStudy} className="flex h-9 items-center gap-1.5 rounded-full border border-slate-200 bg-white px-3 text-sm font-medium text-slate-600 active:bg-slate-100 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300 dark:active:bg-slate-700">
                        <span aria-hidden>⤢</span> Expand All
                      </button>
                      <button onClick={collapseAllStudy} className="flex h-9 items-center gap-1.5 rounded-full border border-slate-200 bg-white px-3 text-sm font-medium text-slate-600 active:bg-slate-100 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300 dark:active:bg-slate-700">
                        <span aria-hidden>⤡</span> Collapse All
                      </button>
                    </div>
                    <div className="space-y-1">{chapterTree.children.map((section) => <StudyNodeRenderer key={section.id} node={section} level={0} expandedSet={expandedNodeIds} scrollToId={scrollToNodeId} collapseSignal={studyCollapseSignal} />)}</div>
                  </div>
                )}
                {chapterTree && mode === "reading" && (
                  <div className={`mx-auto transition-all duration-300 ${focusMode ? "max-w-[62ch]" : "max-w-[70ch]"}`}>
                    {chapterTree.content && <p className="mb-4 font-serif text-slate-700 dark:text-slate-300" style={{ fontSize: `${1.05 * fontScale}rem` }}>{chapterTree.content}</p>}
                    {chapterTree.children.map((section) => <ReadingNodeRenderer key={section.id} node={section} level={0} fontScale={fontScale} expandedSet={expandedNodeIds} scrollToId={scrollToNodeId} />)}
                  </div>
                )}
              </>
            )}
          </main>
        </div>
        {focusMode && mode === "reading" && chapterTree && (
          <button
            onClick={() => setFocusMode(false)}
            className="fixed bottom-6 right-4 z-30 flex items-center gap-1.5 rounded-full bg-navy-900/90 px-4 py-2.5 text-sm font-medium text-white shadow-lg backdrop-blur active:bg-navy-800 dark:bg-slate-100/90 dark:text-navy-900"
          >
            <span aria-hidden>✕</span> Exit Focus
          </button>
        )}
        {showTutorial && <TutorialOverlay onFinish={finishTutorial} />}
      </div>
    </HighlightUIContext.Provider>
  );
}
EOF

# ---------- frontend/src/pages/DevPanel.jsx ----------
cat > frontend/src/pages/DevPanel.jsx << 'EOF'
import QuizPanel from "./QuizPanel";

export default function DevPanel() {
  return (
    <div className="mx-auto max-w-2xl space-y-4 pb-10">
      <div>
        <h1 className="text-2xl font-bold text-slate-900 dark:text-slate-50">🛠 Dev Panel</h1>
        <p className="text-sm text-slate-500 dark:text-slate-400">
          Quiz question import &amp; preview only. This panel is stripped out of production
          builds automatically (it only renders when running{" "}
          <code className="rounded bg-slate-100 px-1 dark:bg-slate-700">npm run dev</code>),
          so it never ships to real users.
        </p>
      </div>
      <QuizPanel />
    </div>
  );
}
EOF

# ---------- frontend/src/pages/QuizPanel.jsx ----------
cat > frontend/src/pages/QuizPanel.jsx << 'EOF'
import { useState, useEffect, useCallback } from "react";
import {
  getAllQuizBatches, getQuizBatchEntries, importQuizJson,
  renameQuizBatch, deleteQuizBatch, getQuizExportAllJson,
  saveRawQuizEntries, clearAllQuizImports, getQuizImportedCount,
} from "../quizStore";
import { LEVELS, QuizLevelButton, QuizPlayView } from "../components/QuizShared";

function QuizBatchCard({ batch, onChanged }) {
  const [open, setOpen] = useState(false);
  const [selectedLevel, setSelectedLevel] = useState(null);
  const [progress, setProgress] = useState({});

  useEffect(() => {
    const storageKey = `quiz_progress_${batch.id}`;
    try {
      setProgress(JSON.parse(localStorage.getItem(storageKey) || "{}"));
    } catch {
      setProgress({});
    }
  }, [batch.id, selectedLevel]);

  const entries = open ? getQuizBatchEntries(batch.id) : [];
  const nodeIds = entries.map((e) => e.id);
  const entriesById = Object.fromEntries(entries.map((e) => [e.id, e]));

  const handleLevelSelect = (levelId) => {
    if (nodeIds.length === 0) { alert("No quiz entries found for this batch."); return; }
    setSelectedLevel(levelId);
  };
  const handleBack = () => setSelectedLevel(null);

  const handleDeleteBatch = () => {
    if (confirm(`Delete the whole "${batch.label}" batch (${batch.nodeIds.length} entries)?`)) {
      deleteQuizBatch(batch.id);
      onChanged();
    }
  };
  const handleRename = () => {
    const next = prompt("Rename this quiz batch:", batch.label);
    if (next !== null) { renameQuizBatch(batch.id, next); onChanged(); }
  };

  if (selectedLevel) {
    return (
      <QuizPlayView
        title={batch.label}
        entries={entriesById}
        level={selectedLevel}
        onBack={handleBack}
        progressKey={batch.id}
      />
    );
  }

  return (
    <div className="rounded-xl border border-slate-200 bg-white p-4 shadow-card dark:border-slate-700 dark:bg-slate-800">
      <div className="mb-3 flex items-center justify-between gap-2">
        <button onClick={() => setOpen((v) => !v)} className="min-w-0 flex-1 text-left">
          <p className="truncate font-semibold text-navy-900 dark:text-slate-100">{open ? "▾" : "▸"} {batch.label}</p>
          <p className="text-xs text-slate-400 dark:text-slate-500">{batch.nodeIds.length} questions · {new Date(batch.importedAt).toLocaleString()}</p>
        </button>
        <div className="flex flex-shrink-0 gap-2">
          <button onClick={handleRename} className="rounded-lg border border-slate-200 px-2.5 py-1 text-xs font-medium text-slate-600 dark:border-slate-600 dark:text-slate-300">✏️</button>
          <button onClick={handleDeleteBatch} className="rounded-lg border border-red-200 px-2.5 py-1 text-xs font-medium text-red-600 dark:border-red-800 dark:text-red-400">Delete</button>
        </div>
      </div>
      {open && (
        <div className="space-y-2">
          {LEVELS.map((level) => (
            <QuizLevelButton key={level.id} level={level} progress={progress[level.id] || 0} onClick={() => handleLevelSelect(level.id)} />
          ))}
        </div>
      )}
    </div>
  );
}

function ImportQuizForm({ onImported }) {
  const [json, setJson] = useState("");
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(null);

  const handleImport = () => {
    setError(null); setSuccess(null);
    try {
      const { count, label } = importQuizJson(json);
      setSuccess(`✓ Imported ${count} questions as "${label}".`);
      setJson("");
      onImported();
    } catch (e) {
      setError(e.message);
    }
  };

  return (
    <div className="rounded-xl border border-navy-200 bg-white p-3 shadow-card dark:border-navy-700 dark:bg-slate-800">
      <p className="mb-1 text-sm font-semibold text-navy-900 dark:text-slate-100">📥 Import Quiz JSON</p>
      <p className="mb-2 text-xs text-slate-400 dark:text-slate-500">Paste the AI-generated quiz JSON and Import — one title per batch. Optional: add "_title" for a custom label (importing the same "_title" again merges into that batch).</p>
      <textarea value={json} onChange={(e) => setJson(e.target.value)} placeholder='{ "_title": "Title II", "4821": { "level1": {...}, "level2": {...}, ... } }' rows={9} style={{ fontSize: "16px" }} className="w-full rounded-lg border border-slate-200 bg-white p-2 font-mono text-xs dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100" />
      {error && <p className="mt-2 text-sm text-red-600 dark:text-red-400">{error}</p>}
      {success && <p className="mt-2 text-sm text-emerald-600 dark:text-emerald-400">{success}</p>}
      <button onClick={handleImport} disabled={!json.trim()} className="mt-2 w-full rounded-lg bg-navy-900 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-40 dark:bg-navy-700">Import</button>
    </div>
  );
}

function RawQuizEditor({ onChanged }) {
  const [open, setOpen] = useState(false);
  const [text, setText] = useState("");
  const [error, setError] = useState(null);
  const [saved, setSaved] = useState(false);

  const openEditor = () => { setText(getQuizExportAllJson()); setOpen(true); setError(null); };
  const handleSave = () => {
    try {
      saveRawQuizEntries(text);
      setError(null); setSaved(true);
      onChanged();
      setTimeout(() => setSaved(false), 2000);
    } catch (e) { setError(e.message); }
  };

  return (
    <div className="rounded-xl border border-slate-200 bg-white p-3 shadow-card dark:border-slate-700 dark:bg-slate-800">
      <button onClick={() => (open ? setOpen(false) : openEditor())} className="text-sm font-semibold text-slate-800 dark:text-slate-100">
        🔧 {open ? "Hide" : "Edit"} Raw Quiz JSON (advanced, all imported data)
      </button>
      {open && (
        <div className="mt-2">
          <textarea value={text} onChange={(e) => setText(e.target.value)} rows={10} style={{ fontSize: "13px" }} className="w-full rounded-lg border border-slate-200 bg-white p-2 font-mono text-xs dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100" />
          {error && <p className="mt-1 text-xs text-red-500">{error}</p>}
          {saved && <p className="mt-1 text-xs text-emerald-600 dark:text-emerald-400">✓ Saved.</p>}
          <button onClick={handleSave} className="mt-2 rounded-lg bg-amber-600 px-3 py-1.5 text-sm font-semibold text-white">Save Raw JSON</button>
        </div>
      )}
    </div>
  );
}

export default function QuizPanel() {
  const [batches, setBatches] = useState([]);
  const [downloaded, setDownloaded] = useState(false);

  const refresh = useCallback(() => setBatches(getAllQuizBatches()), []);
  useEffect(() => { refresh(); }, [refresh]);

  const handleExportAll = () => {
    const json = getQuizExportAllJson();
    const blob = new Blob([json], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const stamp = new Date().toISOString().slice(0, 10);
    const a = document.createElement("a");
    a.href = url;
    a.download = `quiz-export-${stamp}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    setDownloaded(true);
    setTimeout(() => setDownloaded(false), 3500);
  };

  const handleClearAll = () => {
    if (confirm(`Delete ALL ${getQuizImportedCount()} imported quiz entries? This cannot be undone.`)) {
      clearAllQuizImports();
      refresh();
    }
  };

  return (
    <div className="mx-auto max-w-2xl space-y-4 pb-10">
      <div>
        <h1 className="text-2xl font-bold text-slate-900 dark:text-slate-50">📝 Quiz Panel</h1>
        <p className="text-sm text-slate-500 dark:text-slate-400">Import, manage, and test-drive quizzes generated from CMTA provisions.</p>
        <p className="mt-1 text-xs text-slate-400 dark:text-slate-500">
          Kapag tapos ka na sa isang batch, gamitin ang <strong>Export All</strong> tapos i-merge yung JSON sa
          <code className="mx-1 rounded bg-slate-100 px-1 dark:bg-slate-700">frontend/src/data/quizData.json</code>
          para ma-bundle na siya sa app at gumana offline para sa lahat ng users — kagaya ng ginawa mo na sa AI explanations.
        </p>
      </div>

      <ImportQuizForm onImported={refresh} />

      <div className="rounded-xl border border-slate-200 bg-white p-3 shadow-card dark:border-slate-700 dark:bg-slate-800">
        <p className="mb-2 text-sm font-semibold text-slate-800 dark:text-slate-100">📦 All Imported Quizzes ({getQuizImportedCount()} questions)</p>
        <div className="flex flex-wrap gap-2">
          <button onClick={handleExportAll} className="flex-1 rounded-lg bg-emerald-600 px-3 py-2 text-sm font-semibold text-white">⬇️ Export All (download)</button>
          <button onClick={handleClearAll} className="flex-1 rounded-lg border border-red-300 px-3 py-2 text-sm font-semibold text-red-600 dark:border-red-800 dark:text-red-400">🗑 Delete All</button>
        </div>
        {downloaded && <p className="mt-2 text-xs font-medium text-emerald-600 dark:text-emerald-400">✓ Downloaded JSON file.</p>}
      </div>

      <RawQuizEditor onChanged={refresh} />

      <div className="space-y-2">
        <p className="text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500">Imported Quiz Batches</p>
        {batches.length === 0 && <p className="text-sm italic text-slate-400 dark:text-slate-600">No quiz batches imported yet.</p>}
        {batches.map((b) => <QuizBatchCard key={b.id} batch={b} onChanged={refresh} />)}
      </div>
    </div>
  );
}
EOF

# ---------- frontend/src/pages/QuizPage.jsx ----------
cat > frontend/src/pages/QuizPage.jsx << 'EOF'
import { useState, useEffect } from "react";
import staticQuizData from "../data/quizData.json";
import { getFlattenedEntries } from "../quizStore";
import { LEVELS, QuizLevelButton, QuizPlayView } from "../components/QuizShared";

function groupByTitle(flatEntries) {
  const titleGroups = {};
  Object.keys(flatEntries).forEach((id) => {
    const entry = flatEntries[id];
    const title = entry._title || "Untitled";
    if (!titleGroups[title]) titleGroups[title] = {};
    const cleanEntry = { ...entry };
    delete cleanEntry._title;
    titleGroups[title][id] = cleanEntry;
  });
  return Object.keys(titleGroups).map((title) => ({ title, data: titleGroups[title] }));
}

// Live in-browser imports (Dev Panel → Quiz tab) take priority so you can
// preview immediately. Once a batch is finished, export it and merge into
// src/data/quizData.json so it ships with the app and works fully offline
// for every user — same pattern as aiContext.json.
function loadQuizData() {
  try {
    const flat = getFlattenedEntries();
    if (Object.keys(flat).length > 0) return groupByTitle(flat);
  } catch (e) {
    console.warn("Failed to load quiz data from local imports:", e);
  }
  if (staticQuizData && Object.keys(staticQuizData).length > 0) {
    return groupByTitle(staticQuizData);
  }
  return [];
}

function QuizTitleCard({ title, data, onSelectLevel }) {
  const [open, setOpen] = useState(false);
  const [progress, setProgress] = useState({});
  const [totalQuestions, setTotalQuestions] = useState({});

  useEffect(() => {
    const ids = Object.keys(data);
    const counts = {};
    LEVELS.forEach((level) => {
      counts[level.id] = ids.filter((id) => data[id] && data[id][level.id]).length;
    });
    setTotalQuestions(counts);
  }, [data]);

  useEffect(() => {
    const storageKey = `quiz_progress_${title}`;
    try {
      setProgress(JSON.parse(localStorage.getItem(storageKey) || "{}"));
    } catch {
      setProgress({});
    }
  }, [title]);

  const handleLevelSelect = (levelId) => {
    const ids = Object.keys(data).filter((id) => data[id] && data[id][levelId]);
    if (ids.length === 0) {
      alert(`No questions available for ${LEVELS.find((l) => l.id === levelId)?.label}.`);
      return;
    }
    onSelectLevel(title, data, levelId);
  };

  const total = Object.values(totalQuestions).reduce((a, b) => a + b, 0);

  return (
    <div className="rounded-xl border border-slate-200 bg-white p-4 shadow-card dark:border-slate-700 dark:bg-slate-800">
      <div className="mb-3 flex items-center justify-between gap-2">
        <button onClick={() => setOpen((v) => !v)} className="min-w-0 flex-1 text-left">
          <p className="truncate font-semibold text-navy-900 dark:text-slate-100">{open ? "▾" : "▸"} {title}</p>
          <p className="text-xs text-slate-400 dark:text-slate-500">{Object.keys(data).length} provisions · {total} total questions</p>
        </button>
      </div>
      {open && (
        <div className="space-y-2">
          {LEVELS.map((level) => {
            if (!totalQuestions[level.id]) return null;
            return (
              <QuizLevelButton key={level.id} level={level} progress={progress[level.id] || 0} onClick={() => handleLevelSelect(level.id)} />
            );
          })}
        </div>
      )}
    </div>
  );
}

export default function QuizPage() {
  const [selectedTitle, setSelectedTitle] = useState(null);
  const [selectedData, setSelectedData] = useState(null);
  const [selectedLevel, setSelectedLevel] = useState(null);
  const [titles, setTitles] = useState([]);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => { setTitles(loadQuizData()); }, [refreshKey]);

  useEffect(() => {
    const handleStorageChange = (e) => {
      if (e.key === "customsLaw_quizImports") setRefreshKey((prev) => prev + 1);
    };
    window.addEventListener("storage", handleStorageChange);
    return () => window.removeEventListener("storage", handleStorageChange);
  }, []);

  const handleSelectLevel = (title, data, levelId) => {
    setSelectedTitle(title); setSelectedData(data); setSelectedLevel(levelId);
  };
  const handleBack = () => { setSelectedTitle(null); setSelectedData(null); setSelectedLevel(null); };

  if (selectedTitle && selectedData && selectedLevel) {
    return (
      <div className="mx-auto max-w-2xl p-4">
        <QuizPlayView title={selectedTitle} entries={selectedData} level={selectedLevel} onBack={handleBack} progressKey={selectedTitle} backLabel={`← Back to ${selectedTitle}`} />
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl p-4">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-900 dark:text-slate-50">📝 Quiz / Exam</h1>
          <p className="text-sm text-slate-500 dark:text-slate-400">Test your knowledge with 5 levels of difficulty — from Easy to Will Done.</p>
        </div>
        <button onClick={() => setRefreshKey((prev) => prev + 1)} className="rounded-lg border border-slate-200 px-3 py-1.5 text-sm text-slate-600 hover:bg-slate-50 dark:border-slate-600 dark:text-slate-300 dark:hover:bg-slate-800" title="Refresh quiz data from imported files">🔄 Refresh</button>
      </div>

      {titles.length === 0 ? (
        <div className="flex h-64 flex-col items-center justify-center text-center text-slate-500 dark:text-slate-400">
          <p className="text-lg font-medium">No quiz data available</p>
          <p className="text-sm mt-2">Import quiz data from <strong>Dev Panel (🛠) → Quiz tab</strong>.</p>
          <p className="text-sm mt-1">After importing, click <strong>Refresh</strong> or reload the page.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {titles.map(({ title, data }) => <QuizTitleCard key={title} title={title} data={data} onSelectLevel={handleSelectLevel} />)}
        </div>
      )}
    </div>
  );
}
EOF

# ---------- Placeholder JSON files ----------
# aiContext.json (empty, user will fill)
cat > frontend/src/data/aiContext.json << 'EOF'
{}
EOF

# quizData.json (empty, user will fill)
cat > frontend/src/data/quizData.json << 'EOF'
{}
EOF

# ---------- Update config files ----------
# tailwind.config.js
cat > frontend/tailwind.config.js << 'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
        serif: ['"Source Serif 4"', 'Georgia', 'Cambria', 'serif'],
      },
      colors: {
        navy: { 950: '#0b1220', 900: '#0f172a', 800: '#152238', 700: '#1e3a5f' },
        gold: { 50: '#fdf8ec', 100: '#faedc4', 400: '#e0b94d', 500: '#c9a227', 600: '#a9841c' },
      },
    },
  },
  plugins: [],
}
EOF

# vite.config.js (point outDir to '../dist' for APK)
cat > frontend/vite.config.js << 'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    outDir: '../dist',
    emptyOutDir: true,
  },
});
EOF

# index.html (ensure correct paths for APK)
cat > frontend/index.html << 'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
    <meta name="theme-color" content="#0f172a" />
    <meta name="apple-mobile-web-app-capable" content="yes" />
    <meta name="mobile-web-app-capable" content="yes" />
    <title>RA 10863 – Customs Modernization and Tariff Act</title>
    <link rel="manifest" href="/manifest.json" />
    <link rel="apple-touch-icon" href="/icons/icon-192.png" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=Source+Serif+4:opsz,wght@8..60,400;8..60,500;8..60,600;8..60,700&display=swap" rel="stylesheet" />

    <script src="https://cdn.jsdelivr.net/npm/eruda"></script>
    <script>eruda.init();</script>

    <script>
      (function () {
        try {
          if (localStorage.getItem("customsLaw_darkMode") === "true") {
            document.documentElement.classList.add("dark");
          }
        } catch (e) {}
      })();
    </script>

    <script src="https://cdn.tailwindcss.com"></script>
    <script>
      tailwind.config = {
        darkMode: 'class',
        theme: {
          extend: {
            fontFamily: {
              sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
              serif: ['"Source Serif 4"', 'Georgia', 'Cambria', 'serif'],
            },
            colors: {
              navy: { 950: '#0b1220', 900: '#0f172a', 800: '#152238', 700: '#1e3a5f' },
              gold: { 50: '#fdf8ec', 100: '#faedc4', 400: '#e0b94d', 500: '#c9a227', 600: '#a9841c' },
            },
          },
        },
      };
    </script>
    <style>
      html { -webkit-tap-highlight-color: transparent; }
      body { font-family: 'Inter', ui-sans-serif, system-ui, sans-serif; }
      mark { background: #fde68a; padding: 0 2px; border-radius: 3px; color: #1e293b; font-weight: 600; }
      .safe-bottom { padding-bottom: env(safe-area-inset-bottom); }
      .safe-top { padding-top: env(safe-area-inset-top); }
    </style>
  </head>
  <body class="bg-slate-50 text-slate-900 dark:bg-slate-950 dark:text-slate-100">
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOF

# manifest.json (ensure correct paths)
cat > frontend/public/manifest.json << 'EOF'
{
  "name": "RA 10863 - Customs Modernization and Tariff Act",
  "short_name": "CMTA Law",
  "description": "Study and reference companion for the Customs Modernization and Tariff Act (RA 10863) of the Philippines, with search, highlights, and offline support.",
  "id": "/",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "background_color": "#0f172a",
  "theme_color": "#0f172a",
  "orientation": "portrait-primary",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
EOF

# sw.js (same as before)
cat > frontend/public/sw.js << 'EOF'
// Minimal offline-support service worker.
// Strategy: try the network first (so data stays fresh when online),
// and fall back to cache when the request fails (offline / weak signal).
// Every successful GET response gets cached automatically, so chapters,
// search results, and app files you've already opened once will keep
// working with no internet connection.

const CACHE_NAME = "cmta-app-cache-v1";

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  event.respondWith(
    fetch(request)
      .then((response) => {
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(request, copy)).catch(() => {});
        return response;
      })
      .catch(async () => {
        const cached = await caches.match(request);
        if (cached) return cached;
        if (request.mode === "navigate") {
          const shell = await caches.match("/");
          if (shell) return shell;
        }
        return Response.error();
      })
  );
});
EOF

echo "✅ All files updated successfully!"
echo ""
echo "📦 Next steps:"
echo "1. Build the frontend: cd frontend && npm run build"
echo "2. Sync Capacitor: npx cap sync android"
echo "3. Build APK: cd android && ./gradlew assembleDebug"
echo ""
echo "⚠️ IMPORTANT:"
echo "  - The Dev Panel and Download Quiz Template button are hidden in production builds (npm run build) because they are gated behind IS_DEV (which is false in production)."
echo "  - Replace the contents of frontend/src/data/aiContext.json and frontend/src/data/quizData.json with your actual data (you said you'll overwrite them)."
echo "  - The database (customs_law.db) must be present in the frontend/public/ folder for the app to work."
echo ""
echo "Done."
