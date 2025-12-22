# List all available recipes (default)
@default:
    just --list

# Mock Build Testing (for COPR validation)
# - mock-build-srpm: Quick SRPM creation test (no full build)
# - mock-build-rpm: Full SRPM + RPM build in isolated chroot (matches COPR)
#
# Setup (one-time):
#   sudo dnf install -y mock
#   sudo usermod -a -G mock $USER
#   # Then log out and back in, or: newgrp mock
#
# Usage:
#   just mock-build-srpm 1.0.63          # Test SRPM only
#   just mock-build-rpm 1.0.63           # Full build (default: fedora-rawhide-x86_64)
#   just mock-build-rpm 1.0.63 fedora-43-x86_64  # Specific Fedora version

# Core Development

# Run the RimSort application
run: dev-setup
    uv run python -m app

# Run tests with coverage reporting to terminal
test: dev-setup
    uv run pytest --doctest-modules -s --no-qt-log

# Run tests with verbose output and short tracebacks
test-verbose: dev-setup
    uv run pytest --doctest-modules -v --tb=short -s --no-qt-log

# Run tests with full coverage reports (XML, HTML, and terminal)
test-coverage: dev-setup
    uv run pytest --doctest-modules --junitxml=junit/test-results.xml --cov=app --cov-report=xml --cov-report=html --cov-report=term-missing --no-qt-log

# Code Quality

# Check code for linting issues
lint:
    uv run ruff check .

# Check and automatically fix linting issues
lint-fix:
    uv run ruff check . --fix

# Check code formatting without making changes
format:
    uv run ruff format . --check

# Format code automatically
format-fix:
    uv run ruff format .

# Run type checking with mypy
typecheck:
    uv run mypy --config-file pyproject.toml .

# Run all code quality checks (lint, format, typecheck)
check: lint format typecheck

# Automatically fix linting and formatting issues
fix: lint-fix format-fix
    @echo "Auto-fixes applied!"

# Run full CI pipeline (all checks + tests with coverage)
ci: check test-coverage
    @echo "CI simulation complete!"

## Dependency Management
# Install all dependencies including dev and build groups
dev-setup: submodules-init
    uv venv --allow-existing
    uv sync --locked --dev --group build

# Update all dependencies to latest compatible versions
update:
    uv lock --upgrade

# Remove all build artifacts, caches, and generated files
clean:
    rm -rf build/ dist/ *.egg-info
    rm -rf .pytest_cache .mypy_cache .ruff_cache
    rm -rf htmlcov .coverage coverage.xml
    rm -rf junit/
    find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

# Build/Distribution

# Build RimSort executable
build *ARGS='': submodules-init check
    uv run python distribute.py {{ARGS}}

# Build RimSort executable with specific version (e.g., "1.2.3.4")
build-version VERSION: submodules-init check
    uv run python distribute.py --product-version="{{VERSION}}"

# Create source tarball with submodules for RPM building
rpm-tarball VERSION='0.0.0~git':
    #!/usr/bin/env bash
    set -euo pipefail

    # Auto-append .1 if version has only 3 parts (for Nuitka compatibility)
    PART_COUNT=$(echo "{{VERSION}}" | tr '.' '\n' | wc -l)
    if [ "$PART_COUNT" -eq 3 ]; then
        FULL_VERSION="{{VERSION}}.1"
    else
        FULL_VERSION="{{VERSION}}"
    fi

    # Call existing script to create tarball
    bash packaging/rpm/make-tarball.sh "$FULL_VERSION"

# Build RPM package for Fedora/RHEL (e.g., just build-rpm 1.0.63 or just build-rpm 1.0.63.1)
build-rpm VERSION='0.0.0~git': check (rpm-tarball VERSION)
    #!/usr/bin/env bash
    set -euo pipefail

    # Auto-append .1 if version has only 3 parts (for Nuitka compatibility)
    PART_COUNT=$(echo "{{VERSION}}" | tr '.' '\n' | wc -l)
    if [ "$PART_COUNT" -eq 3 ]; then
        FULL_VERSION="{{VERSION}}.1"
    else
        FULL_VERSION="{{VERSION}}"
    fi

    echo "Setting up RPM build environment..."
    mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

    echo "Building RPM package for version $FULL_VERSION..."
    rpmbuild -bb packaging/rpm/rimsort.spec --define "version $FULL_VERSION"

    echo "RPM build complete!"
    RPM_FILE=$(find ~/rpmbuild/RPMS/x86_64/ -name "rimsort-$FULL_VERSION-*.rpm" | head -n 1)
    if [ -n "$RPM_FILE" ]; then
        echo "Built RPM: $RPM_FILE"
        ls -lh "$RPM_FILE"
    else
        echo "Warning: Could not find built RPM"
    fi

# Build RPM using Mock (COPR-like environment) - tests SRPM creation + RPM build
mock-build-rpm VERSION='0.0.0~git' MOCK_CONFIG='fedora-rawhide-x86_64':
    #!/usr/bin/env bash
    set -euo pipefail

    # Auto-append .1 if version has only 3 parts
    PART_COUNT=$(echo "{{VERSION}}" | tr '.' '\n' | wc -l)
    if [ "$PART_COUNT" -eq 3 ]; then
        FULL_VERSION="{{VERSION}}.1"
    else
        FULL_VERSION="{{VERSION}}"
    fi

    echo "Testing COPR build locally with Mock..."
    echo "Version: $FULL_VERSION"
    echo "Mock config: {{MOCK_CONFIG}}"

    # Create SRPM using the same .copr/Makefile that COPR uses
    OUTDIR=$(mktemp -d)

    echo "==> Building SRPM (using .copr/Makefile)"
    make -f .copr/Makefile srpm \
        outdir="$OUTDIR" \
        spec="$(pwd)/packaging/rpm/rimsort.spec"

    SRPM=$(find "$OUTDIR" -name '*.src.rpm' | head -n 1)
    if [ -z "$SRPM" ]; then
        echo "ERROR: SRPM not found in $OUTDIR"
        exit 1
    fi

    echo "==> SRPM created: $SRPM"

    # Build RPM using Mock (same as COPR does)
    echo "==> Building RPM with Mock"
    mock -r {{MOCK_CONFIG}} --rebuild "$SRPM" --resultdir="$OUTDIR/mock-results" --no-cleanup-after || true

    # Keep the results (even if build failed)
    KEEP_DIR="$HOME/mock-builds/rimsort-$FULL_VERSION-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$(dirname "$KEEP_DIR")"
    if [ -d "$OUTDIR/mock-results" ]; then
        cp -r "$OUTDIR/mock-results" "$KEEP_DIR"
        echo "Results saved to: $KEEP_DIR"
        echo "Build log: $KEEP_DIR/build.log"

        # Show last 50 lines of build log if it exists
        if [ -f "$KEEP_DIR/build.log" ]; then
            echo "==> Last 50 lines of build.log:"
            tail -50 "$KEEP_DIR/build.log"
        fi
    else
        echo "WARNING: No mock results found at $OUTDIR/mock-results"
    fi

# Quick SRPM-only test (faster iteration without full Mock build)
mock-build-srpm VERSION='0.0.0~git':
    #!/usr/bin/env bash
    set -euo pipefail

    # Auto-append .1 if version has only 3 parts
    PART_COUNT=$(echo "{{VERSION}}" | tr '.' '\n' | wc -l)
    if [ "$PART_COUNT" -eq 3 ]; then
        FULL_VERSION="{{VERSION}}.1"
    else
        FULL_VERSION="{{VERSION}}"
    fi

    echo "Testing SRPM creation only..."
    echo "Version: $FULL_VERSION"

    OUTDIR=$(mktemp -d)

    make -f .copr/Makefile srpm \
        outdir="$OUTDIR" \
        spec="$(pwd)/packaging/rpm/rimsort.spec"

    echo "==> SRPM created successfully:"
    ls -lh "$OUTDIR"/*.src.rpm

    # Optionally inspect contents
    echo -e "\n==> SRPM contents:"
    rpm -qlp "$OUTDIR"/*.src.rpm

# Utilities

# Initialize and update git submodules (run after cloning)
submodules-init:
    git submodule update --init --recursive

# Show help for distribute.py build script
build-help:
    uv run python ./distribute.py --help
