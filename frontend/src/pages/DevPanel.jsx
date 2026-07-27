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
