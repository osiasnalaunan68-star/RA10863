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
