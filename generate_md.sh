#!/data/data/com.termux/files/usr/bin/bash

OUTPUT="full_code_dump.md"
echo "# Full Code Dump for RA10863" > "$OUTPUT"
echo "Generated on: $(date)" >> "$OUTPUT"
echo "" >> "$OUTPUT"

# 1. Directory tree (3 levels)
echo "## Project Structure" >> "$OUTPUT"
echo '```' >> "$OUTPUT"
if command -v tree &>/dev/null; then
    tree -L 3 -d >> "$OUTPUT" 2>/dev/null || echo "tree not available" >> "$OUTPUT"
else
    find . -maxdepth 3 -type d | sort >> "$OUTPUT"
fi
echo '```' >> "$OUTPUT"
echo "" >> "$OUTPUT"

# 2. Text file extensions we want to include
EXTENSIONS=(
    .js .jsx .ts .tsx .json .html .css .scss .md .yaml .yml
    .gradle .properties .xml .sh .bash .conf .config .toml
    .py .pyx .pyd .txt .rb .go .rs .c .cpp .h .java .kt .kts
)

# Build find command to exclude junk
find_cmd="find . -type f"
# Exclude folders
for dir in node_modules .git dist build android/build android/app/build android/.gradle backups __pycache__ .idea .vscode; do
    find_cmd="$find_cmd -not -path \"*/$dir/*\""
done
# Exclude binary extensions
for ext in .png .jpg .jpeg .gif .ico .svg .mp3 .mp4 .wav .flac .zip .gz .tar .rar .7z .db .sqlite .wasm .apk .aab .jar .class .so .dylib .dll .obj .o .pyc; do
    find_cmd="$find_cmd -not -name \"*$ext\""
done

# Process each file
eval "$find_cmd" | while read -r file; do
    # Check extension
    ext="${file##*.}"
    include=0
    for allowed in "${EXTENSIONS[@]}"; do
        if [[ ".$ext" == "$allowed" ]]; then
            include=1
            break
        fi
    done
    # Also include files like Dockerfile, Makefile, etc. (no extension)
    if [[ $include -eq 0 ]]; then
        basename=$(basename "$file")
        case "$basename" in
            Dockerfile|Makefile|README|LICENSE|Cargo.toml|Cargo.lock)
                include=1 ;;
        esac
    fi
    if [[ $include -eq 1 ]]; then
        # Skip if file is > 500KB (likely generated or large text)
        size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
        if [ -n "$size" ] && [ "$size" -gt 524288 ]; then
            echo "## File: $file (SKIPPED - >500KB)" >> "$OUTPUT"
            echo "" >> "$OUTPUT"
            continue
        fi
        echo "## File: $file" >> "$OUTPUT"
        echo '```' >> "$OUTPUT"
        cat "$file" 2>/dev/null >> "$OUTPUT"
        echo '```' >> "$OUTPUT"
        echo "" >> "$OUTPUT"
    fi
done

echo "Dump created: $OUTPUT"
