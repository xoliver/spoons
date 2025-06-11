#!/bin/bash

# Set source and destination directories
SRC_DIR="src"
ZIP_DIR="Spoons"

# Ensure destination directory exists
mkdir -p "$ZIP_DIR"

# Loop through each folder in SRC_DIR
for dir in "$SRC_DIR"/*/; do
    folder_name=$(basename "$dir")

	# zip_path="$ZIP_DIR/$folder_name.zip"

    # Remove existing zip if it exists
    # [ -f "$zip_path" ] && rm "$zip_path"

    # Go to the parent directory of the folder, then zip the folder itself
    (
        cd "$SRC_DIR" || exit
        zip -r "../$ZIP_DIR/$folder_name.zip" "$folder_name"
    )
done
