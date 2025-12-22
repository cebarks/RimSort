#!/bin/bash
# Create source tarball with submodules for RPM building

set -e

VERSION="${1:-0.0.0~git}"
TARBALL="$HOME/rpmbuild/SOURCES/rimsort-$VERSION.tar.gz"

echo "Creating source tarball with submodules..."

# Create temporary directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Archive main repository
git archive --prefix="RimSort-$VERSION/" HEAD | tar -x -C "$TMPDIR"

# Archive submodules
git submodule foreach --quiet "git archive --prefix=\"RimSort-$VERSION/\$displaypath/\" HEAD | tar -x -C \"$TMPDIR\""

# Include uv cache if it exists (for offline builds in mock/COPR)
if [ -d ".uv-cache" ]; then
    echo "Including uv cache for offline build..."
    cp -r ".uv-cache" "$TMPDIR/RimSort-$VERSION/"
    du -sh "$TMPDIR/RimSort-$VERSION/.uv-cache"
fi

# Include todds if it exists (for offline builds in mock/COPR)
if [ -d "todds" ]; then
    echo "Including todds for offline build..."
    cp -r "todds" "$TMPDIR/RimSort-$VERSION/"
    ls -lh "$TMPDIR/RimSort-$VERSION/todds/"
fi

# Create the final tarball
cd "$TMPDIR"
tar -czf "$TARBALL" "RimSort-$VERSION"

echo "Tarball created: $TARBALL"
ls -lh "$TARBALL"
