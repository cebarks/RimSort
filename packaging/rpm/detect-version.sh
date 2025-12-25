#!/usr/bin/env bash
# Detect version from git tags with Nuitka compatibility

provided="${1:-}"

# Use provided version if given
if [ -n "$provided" ]; then
    VERSION="$provided"
else
    # Detect from git tags
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed "s/^v//" || echo "")
    if [ -z "$VERSION" ]; then
        # Fallback to commit-based version
        VERSION="0.0.0.git~$(git rev-parse --short HEAD)"
    fi
fi

# Auto-append .1 for Nuitka if version has only 3 parts
PART_COUNT=$(echo "$VERSION" | tr "." "\n" | wc -l)
if [ "$PART_COUNT" -eq 3 ]; then
    echo "$VERSION.1"
else
    echo "$VERSION"
fi
