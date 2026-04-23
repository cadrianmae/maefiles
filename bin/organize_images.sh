#!/bin/bash

# Usage: ./organize_images.sh <source_folder> <destination_folder>

SOURCE="$1"
DEST="$2"

# Check if both arguments provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <source_folder> <destination_folder>"
    exit 1
fi

# Check if source exists
if [ ! -d "$SOURCE" ]; then
    echo "Source folder doesn't exist: $SOURCE"
    exit 1
fi

# Create destination if it doesn't exist
mkdir -p "$DEST"

# Process each image file (all common formats)
find "$SOURCE" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.tif" -o -iname "*.cr2" -o -iname "*.cr3" -o -iname "*.nef" -o -iname "*.arw" -o -iname "*.dng" -o -iname "*.orf" -o -iname "*.rw2" -o -iname "*.pef" -o -iname "*.srw" -o -iname "*.webp" -o -iname "*.heic" -o -iname "*.avif" \) | while read -r file; do
    # Get file modification date
    file_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$file" 2>/dev/null || stat -c "%y" "$file" | cut -d' ' -f1)

    # Extract year and month
    year=$(echo "$file_date" | cut -d'-' -f1)
    month=$(echo "$file_date" | cut -d'-' -f2)

    # Get just the filename
    filename=$(basename "$file")

    # Create directory structure
    dest_dir="$DEST/$year/$month"
    mkdir -p "$dest_dir"

    # Copy with new name format
    cp "$file" "$dest_dir/${file_date}_${filename}"
    echo "Copied: $filename → $dest_dir/${file_date}_${filename}"
done

echo "Done organizing images! ✨"
