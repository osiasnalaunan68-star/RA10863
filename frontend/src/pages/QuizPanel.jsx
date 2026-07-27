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
