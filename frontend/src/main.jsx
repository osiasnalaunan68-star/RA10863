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
