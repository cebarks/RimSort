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

# Initialize and update git submodules
echo "Initializing git submodules..."
git submodule update --init --recursive

# Create source tarball with submodules
echo "Creating source tarball with submodules..."
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Archive main repository
git archive --prefix="RimSort-$FULL_VERSION/" HEAD | tar -x -C "$TMPDIR"

# Archive each submodule
git submodule foreach --quiet "git archive --prefix=\"RimSort-$FULL_VERSION/\$displaypath/\" HEAD | tar -x -C \"$TMPDIR\""

# Create final tarball
cd "$TMPDIR"
tar -czf "$outdir/rimsort-$FULL_VERSION.tar.gz" "RimSort-$FULL_VERSION"
echo "Tarball created: $outdir/rimsort-$FULL_VERSION.tar.gz"

# Build SRPM using rpmbuild
echo "Building SRPM..."
rpmbuild -bs "$spec" \
    --define "_sourcedir $outdir" \
    --define "_srcrpmdir $outdir" \
    --define "version $FULL_VERSION"

echo "=== SRPM Build Complete ==="
echo "SRPM created: $(ls $outdir/*.src.rpm)"
ls -lh "$outdir"/*.src.rpm
