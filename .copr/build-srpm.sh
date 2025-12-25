#!/bin/bash
set -euo pipefail

echo "=== COPR SRPM Build for RimSort ==="

# Detect version from git tags
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed "s/^v//" || echo "")
if [ -z "$VERSION" ]; then
    echo "No git tag found, using commit-based version"
    VERSION="0.0.0.git$(git rev-parse --short HEAD)"
fi
echo "Detected version: $VERSION"

# Auto-append .1 for Nuitka if version has only 3 parts
PART_COUNT=$(echo "$VERSION" | tr "." "\n" | wc -l)
if [ "$PART_COUNT" -eq 3 ]; then
    FULL_VERSION="$VERSION.1"
    echo "Auto-appended .1 for Nuitka compatibility: $FULL_VERSION"
else
    FULL_VERSION="$VERSION"
fi

echo "Building SRPM for version $FULL_VERSION"

# Initialize git submodules
echo "Initializing git submodules..."
git submodule update --init --recursive

# Create source tarball using existing script
packaging/rpm/make-tarball.sh "$FULL_VERSION" "$outdir"

# Build SRPM using rpmbuild
echo "Building SRPM..."
rpmbuild -bs "$spec" \
    --define "_sourcedir $outdir" \
    --define "_srcrpmdir $outdir" \
    --define "version $FULL_VERSION"

echo "=== SRPM Build Complete ==="
echo "SRPM created: $(ls $outdir/*.src.rpm)"
ls -lh "$outdir"/*.src.rpm
