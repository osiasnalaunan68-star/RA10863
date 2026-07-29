#!/bin/bash
# Output all code files as Markdown with language hints

OUTPUT="all_files.md"
> "$OUTPUT"  # Clear or create file

# List of file extensions to include (text-based code)
extensions=(
    "*.py" "*.js" "*.jsx" "*.ts" "*.tsx"
    "*.css" "*.scss" "*.html"
    "*.json" "*.yaml" "*.yml" "*.toml"
    "*.md" "*.txt"
    "*.sh" "*.bash"
    "*.sql"
    "*.xml" "*.xsd"
    "*.conf" "*.config" "*.ini"
)

# Build find command
find_cmd="find . -type f \( "
first=true
for ext in "${extensions[@]}"; do
    if [ "$first" = true ]; then
        find_cmd+="-name \"$ext\""
        first=false
    else
        find_cmd+=" -o -name \"$ext\""
    fi
done
find_cmd+=" \)"

# Exclude directories
exclude_dirs=(
    "*/node_modules/*"
    "*/__pycache__/*"
    "*/venv/*"
    "*/env/*"
    "*/docs/assets/*"
    "*/docs/icons/*"
    "*/.git/*"
    "*/dist/*"
    "*/build/*"
)
for dir in "${exclude_dirs[@]}"; do
    find_cmd+=" -not -path \"$dir\""
done

# Exclude specific files
find_cmd+=" -not -name \"package-lock.json\""
find_cmd+=" -not -name \"yarn.lock\""
find_cmd+=" -not -name \"*.db\""
find_cmd+=" -not -name \"*.wasm\""
find_cmd+=" -not -name \"*.png\""
find_cmd+=" -not -name \"*.jpg\""
find_cmd+=" -not -name \"*.jpeg\""
find_cmd+=" -not -name \"*.gif\""
find_cmd+=" -not -name \"*.ico\""
find_cmd+=" -not -name \"*.svg\""

# Process each file
eval $find_cmd | while read -r file; do
    # Determine language for code block based on extension
    lang="${file##*.}"
    case "$lang" in
        py) lang="python" ;;
        js) lang="javascript" ;;
        jsx) lang="jsx" ;;
        ts) lang="typescript" ;;
        tsx) lang="tsx" ;;
        css) lang="css" ;;
        scss) lang="scss" ;;
        html) lang="html" ;;
        json) lang="json" ;;
        yaml|yml) lang="yaml" ;;
        toml) lang="toml" ;;
        md) lang="markdown" ;;
        sh|bash) lang="bash" ;;
        sql) lang="sql" ;;
        xml) lang="xml" ;;
        conf|config|ini) lang="ini" ;;
        *) lang="" ;;
    esac

    # Write to markdown
    echo "## File: \`$file\`" >> "$OUTPUT"
    echo '```'"$lang" >> "$OUTPUT"
    cat "$file" >> "$OUTPUT"
    echo '```' >> "$OUTPUT"
    echo >> "$OUTPUT"
done

echo "Done! Output written to $OUTPUT"
