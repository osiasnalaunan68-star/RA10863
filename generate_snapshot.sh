#!/bin/bash

# Generate a complete markdown snapshot of the entire project
# Usage: ./generate_snapshot.sh [project_root]
# Default: current directory

PROJECT_ROOT="${1:-.}"
OUTPUT="project_snapshot.md"

echo "# Project Snapshot" > "$OUTPUT"
echo "Generated on: $(date)" >> "$OUTPUT"
echo "Root directory: $(cd "$PROJECT_ROOT" && pwd)" >> "$OUTPUT"
echo "" >> "$OUTPUT"
echo "## Directory Structure" >> "$OUTPUT"
echo "\`\`\`" >> "$OUTPUT"
# tree if available, else fallback to find
if command -v tree >/dev/null 2>&1; then
  (cd "$PROJECT_ROOT" && tree -a -I '.git|node_modules|dist|__pycache__|*.pyc|.venv|env|.env' --noreport) >> "$OUTPUT"
else
  (cd "$PROJECT_ROOT" && find . -type f -not -path '*/\.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/__pycache__/*' | sort) >> "$OUTPUT"
fi
echo "\`\`\`" >> "$OUTPUT"
echo "" >> "$OUTPUT"
echo "## File Contents" >> "$OUTPUT"

# Find and process each file (excluding binary, large files, etc.)
(cd "$PROJECT_ROOT" && find . -type f \
  -not -path '*/\.git/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/dist/*' \
  -not -path '*/__pycache__/*' \
  -not -name '*.pyc' \
  -not -name '*.log' \
  -not -name '*.db' \
  -not -name '*.sqlite3' \
  -not -name '*.png' \
  -not -name '*.jpg' \
  -not -name '*.ico' \
  -not -name '*.svg' \
  -not -name '*.woff2' \
  -not -name '*.woff' \
  -not -name '*.ttf' \
  -not -name '*.eot' \
  -not -name '*.otf' \
  -not -name '*.zip' \
  -not -name '*.tar.gz' \
  -not -name '*.tgz' \
  -not -name '*.gz' \
  -not -name '*.bz2' \
  -not -name '*.xz' \
  -not -name '*.7z' \
  -not -name '*.rar' \
  -not -name '*.mp4' \
  -not -name '*.mp3' \
  -not -name '*.wav' \
  -not -name '*.flac' \
  -not -name '*.webm' \
  -not -name '*.pdf' \
  -not -name '*.docx' \
  -not -name '*.xlsx' \
  -not -name '*.pptx' \
  -not -name '*.key' \
  -not -name '*.pem' \
  -not -name '*.crt' \
  -not -name '*.key' \
  -not -name '*.pub' \
  -not -name '*.lock' \
  -not -name 'package-lock.json' \
  -not -name 'yarn.lock' \
  -not -name 'pnpm-lock.yaml' \
  -not -name 'Cargo.lock' \
  -not -name 'Gemfile.lock' \
  -not -name 'poetry.lock' \
  -not -name '*.log' \
  -not -name '*.tmp' \
  -not -name '*.swp' \
  -not -name '*.swo' \
  -not -name '*.bak' \
  -not -name '*.old' \
  -not -path '*/migrations/*' \
  -not -path '*/venv/*' \
  -not -path '*/env/*' \
  -not -path '*/.env/*' \
  -not -path '*/__pycache__/*' \
  -not -path '*/\.pytest_cache/*' \
  -not -path '*/\.mypy_cache/*' \
  -not -path '*/\.ruff_cache/*' \
  -not -path '*/\.coverage/*' \
  -not -name '*.egg-info' \
  -not -path '*/build/*' \
  -not -path '*/dist/*' \
  -print0 | while IFS= read -r -d '' file; do
    # Skip if it's a binary (using file command)
    if file -b --mime-type "$file" 2>/dev/null | grep -q '^text/'; then
      echo "" >> "$OUTPUT"
      echo "### \`$file\`" >> "$OUTPUT"
      echo "\`\`\`$(echo "$file" | sed 's/.*\.//' | tr '[:upper:]' '[:lower:]')" >> "$OUTPUT"
      cat "$file" >> "$OUTPUT" 2>/dev/null || echo "--- Error reading file ---" >> "$OUTPUT"
      echo "\`\`\`" >> "$OUTPUT"
    fi
  done
)

echo "" >> "$OUTPUT"
echo "--- End of snapshot ---" >> "$OUTPUT"

echo "✅ Snapshot generated: $OUTPUT"
