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
