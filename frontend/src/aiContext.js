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
