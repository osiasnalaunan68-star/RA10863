#!/data/data/com.termux/files/usr/bin/bash

FILE="frontend/src/pages/ChapterBrowser.jsx"

# Backup original
cp "$FILE" "$FILE.bak"

# 1. Replace the import line for aiExplanations
sed -i 's|import aiExplanations from "../data/aiExplanations.json";|import staticAiExplanations from "../data/aiExplanations.json";|' "$FILE"

# 2. Replace getAiExplanation function with new version that uses state
# We'll insert a new function that uses a global variable, but easier: we'll replace the function definition.
# We'll use a heredoc to insert a new function after imports.
# Since sed can't easily handle multi-line, we'll use a temporary file.

# We'll create a new file with the new function and insert it after the imports.
cat > /tmp/new_getAiExplanation.js << 'INNER'
// Get AI explanation from combined sources (static + dynamic)
let dynamicExplanations = {};
export function setDynamicExplanations(data) {
  dynamicExplanations = data;
}
function getAiExplanation(node) {
  if (!node) return null;
  const key = `${node.node_type}:${node.node_number}`;
  // Merge: dynamic overrides static
  const all = { ...staticAiExplanations, ...dynamicExplanations };
  return all[key] || null;
}
INNER

# Insert after the import lines (we'll find the line with "import staticAiExplanations" and insert after that)
# We'll use sed to insert the content of /tmp/new_getAiExplanation.js after that line.
# But we need to remove the old getAiExplanation function. We'll delete the old one.
# The old function is:
# function getAiExplanation(node) {
#   if (!node) return null;
#   const key = `${node.node_type}:${node.node_number}`;
#   return aiExplanations[key] || null;
# }
# We'll replace it with a placeholder and then insert the new one.

# Simpler approach: replace the entire function definition block with a placeholder and then insert new.
# We'll use a marker.

# We'll just provide the whole new file via cat, but that's long. However, we can use a smaller patch.

# Since the user wants a simple solution, I'll provide the entire modified ChapterBrowser.jsx as a separate file in the answer.
# I'll create a heredoc with the full file, but it's long. But it's okay for the answer.

# I'll skip this script and just give the full file content in the answer.

