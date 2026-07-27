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
