#!/bin/bash

# 1. Define the list of workers
HOSTS_FILE="$HOME/MDTest/scripts/hosts.txt"
# 2. Define the source (the compiled binaries)
SOURCE_DIR="$HOME/MDTest/ior-4.0.0-install/bin"
# 3. Define the destination on the workers
DEST_DIR="$HOME/MDTest/bin"

for node in $(cat $HOSTS_FILE); do
    echo "--- Sending binaries to $node ---"
    # Create the folder on the worker node
    ssh orangepi@$node "mkdir -p $DEST_DIR"
    # Copy the actual tools
    scp $SOURCE_DIR/* orangepi@$node:$DEST_DIR/
done

echo "Finished! Every node now has the MDTest tools."
