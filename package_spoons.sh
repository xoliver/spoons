#!/bin/bash

# Set source and destination directories
SRC_DIR="src"
DIST_DIR="Spoons"

# Create dist directory if it doesn't exist
mkdir -p "$DIST_DIR"

# Loop over each subdirectory in src
for dir in "$SRC_DIR"/*/; do
    # Check if it is a directory
    if [ -d "$dir" ]; then
        # Get the name of the subdirectory without the path
        folder_name=$(basename "$dir")
        # Create the zip file in dist with the same folder name
        zip -r "$DIST_DIR/$folder_name.zip" "$dir"
		echo "Zipped $folder_name"
    fi
done

echo "Zipping complete."
