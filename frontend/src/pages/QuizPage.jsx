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
