#!/usr/bin/env bash

### ============================================================
### split_compress_recursive.sh
###  - Recursively collect ALL files under a folder (subdirs too)
###  - Split them into N groups
###  - Create N tar.gz archives, preserving relative paths
### ============================================================

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <target_folder> <number_of_archives>"
    exit 1
fi

TARGET_DIR="$1"
ARCHIVE_COUNT="$2"

# Validate folder
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: '$TARGET_DIR' is not a directory."
    exit 1
fi

# Validate archive number
if ! [[ "$ARCHIVE_COUNT" =~ ^[0-9]+$ ]] || [ "$ARCHIVE_COUNT" -le 0 ]; then
    echo "Error: Archive count must be a positive integer."
    exit 1
fi

# Collect ALL files under TARGET_DIR (recursively), as relative paths
# e.g. ./file, ./subdir/file2, ...
echo "Collecting files recursively under: $TARGET_DIR"
mapfile -t FILES < <(cd "$TARGET_DIR" && find . -type f | sort)

TOTAL_FILES="${#FILES[@]}"

if [ "$TOTAL_FILES" -eq 0 ]; then
    echo "No files found in the folder (recursively)."
    exit 1
fi

echo "Found $TOTAL_FILES files (including subdirectories)."
echo "Splitting into $ARCHIVE_COUNT archives..."

# Compute files per archive (ceil division)
FILES_PER_ARCHIVE=$(( (TOTAL_FILES + ARCHIVE_COUNT - 1) / ARCHIVE_COUNT ))

echo "Files per archive (approx): $FILES_PER_ARCHIVE"
echo

OUTPUT_DIR="./archives_output"
mkdir -p "$OUTPUT_DIR"

index=0
part=1

while [ "$index" -lt "$TOTAL_FILES" ]; do
    start="$index"
    end=$(( index + FILES_PER_ARCHIVE ))
    [ "$end" -gt "$TOTAL_FILES" ] && end="$TOTAL_FILES"

    GROUP_FILES=("${FILES[@]:$start:$((end-start))}")

    ARCHIVE_NAME=$(printf "%s/archive_part_%02d.tar.gz" "$OUTPUT_DIR" "$part")

    echo "Creating $ARCHIVE_NAME with files:"
    for relpath in "${GROUP_FILES[@]}"; do
        echo " - $relpath"
    done

    # IMPORTANT:
    #  -C "$TARGET_DIR" : change directory before adding files
    #  GROUP_FILES are relative paths like ./subdir/file.txt
    tar -czvf "$ARCHIVE_NAME" -C "$TARGET_DIR" "${GROUP_FILES[@]}"

    echo "Done part $part"
    echo

    index=$end
    part=$((part+1))
done

echo "All archives created in: $OUTPUT_DIR"
