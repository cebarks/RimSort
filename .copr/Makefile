# .copr/Makefile
# SRPM build script for Copr (Fedora build system)
#
# Copr invokes this with: make -f .copr/Makefile srpm outdir="<outdir>" spec="<spec_path>"
#
# This Makefile:
# 1. Extracts version from git tags
# 2. Installs required build dependencies (git, rpm-build, rpmdevtools)
# 3. Creates source tarball with submodules using git archive
# 4. Builds SRPM and places it in outdir for Copr to consume

# Default target - invoked by Copr
.PHONY: srpm
srpm: install-deps fetch-tags populate-uv-cache download-todds
	@echo "==> Building SRPM for RimSort"
	@$(MAKE) -f .copr/Makefile create-tarball
	@$(MAKE) -f .copr/Makefile build-srpm

# Install required dependencies in the mock chroot
# Copr runs in a minimal environment, so we need to install tools
.PHONY: install-deps
install-deps:
	@echo "==> Installing build dependencies"
	@if ! command -v git &> /dev/null; then \
		dnf install -y git; \
	fi
	@if ! command -v rpmbuild &> /dev/null; then \
		dnf install -y rpm-build rpmdevtools; \
	fi
	@if ! command -v uv &> /dev/null; then \
		dnf install -y uv; \
	fi
	@if ! command -v python3.12 &> /dev/null; then \
		dnf install -y python3.12; \
	fi
	# Install libgomp - required by rpmbuild at runtime in Fedora 43+
	# Without this, rpmbuild -bs fails with "error while loading shared libraries: libgomp.so.1"
	@dnf install -y libgomp

# Fetch git tags from remote if not already available
# COPR clones the repo but doesn't fetch tags by default
.PHONY: fetch-tags
fetch-tags:
	@echo "==> Ensuring git tags are available"
	@if git rev-parse --is-inside-work-tree &> /dev/null; then \
		if git describe --tags --abbrev=0 &> /dev/null 2>&1; then \
			echo "Git tags already available"; \
		else \
			echo "Git tags not found, fetching from remote..."; \
			REMOTE=$$(git remote | head -n 1); \
			if [ -z "$$REMOTE" ]; then \
				echo "ERROR: No git remote configured"; \
				exit 1; \
			fi; \
			echo "Using remote: $$REMOTE"; \
			git fetch --tags "$$REMOTE" || { \
				echo "ERROR: Failed to fetch tags from remote $$REMOTE"; \
				exit 1; \
			}; \
			echo "Git tags fetched successfully"; \
			TAG_COUNT=$$(git tag -l | wc -l); \
			echo "Number of tags available: $$TAG_COUNT"; \
			if [ "$$TAG_COUNT" -eq 0 ]; then \
				echo "WARNING: No tags found after fetch!"; \
				echo "Listing remotes:"; \
				git remote -v; \
			fi; \
		fi; \
	else \
		echo "ERROR: Not in a git repository"; \
		exit 1; \
	fi

# Populate uv cache for offline builds in mock/COPR
# This allows the RPM build phase to install dependencies without network access
.PHONY: populate-uv-cache
populate-uv-cache:
	@echo "==> Populating uv cache for offline builds"

	# Remove existing .venv and cache to force fresh download
	@rm -rf .venv .uv-cache
	@mkdir -p .uv-cache

	# Set cache directory and populate it by syncing dependencies
	# Include dev dependencies and build group to ensure all packages are available
	# Explicitly use python3.12 to match pyproject.toml requirements
	UV_CACHE_DIR=$(CURDIR)/.uv-cache uv sync --locked --group build --python python3.12

	@echo "uv cache populated at: $(CURDIR)/.uv-cache"
	@du -sh "$(CURDIR)/.uv-cache"

# Download todds for offline builds
# todds is a texture optimization tool used during the build
.PHONY: download-todds
download-todds:
	@echo "==> Downloading todds for offline build"
	@.venv/bin/python distribute.py --skip-build --skip-submodules
	@echo "todds downloaded to: $(CURDIR)/todds/"
	@ls -lh "$(CURDIR)/todds/" 2>/dev/null || echo "Warning: todds directory not found"

# Extract version from git tag and create source tarball
# Reuses existing packaging/rpm/make-tarball.sh script
.PHONY: create-tarball
create-tarball:
	@echo "==> Creating source tarball with submodules"

	# Extract version from git tag (strip 'v' prefix)
	# Example: v1.0.63 -> 1.0.63
	$(eval VERSION := $(shell git describe --tags --abbrev=0 | sed 's/^v//'))
	@if [ -z "$(VERSION)" ]; then \
		echo "ERROR: Could not determine version from git tags"; \
		echo "ERROR: Ensure tags are fetched with: git fetch --tags origin"; \
		exit 1; \
	fi
	@echo "Detected version: $(VERSION)"

	# Create rpmbuild directory structure (script expects this)
	@mkdir -p $$HOME/rpmbuild/SOURCES

	# Call existing script to create tarball with submodules
	@bash packaging/rpm/make-tarball.sh "$(VERSION)"

	# Copy tarball to current directory where rpmbuild can find it
	@cp $$HOME/rpmbuild/SOURCES/rimsort-$(VERSION).tar.gz $(CURDIR)/
	@echo "Tarball copied to: $(CURDIR)/rimsort-$(VERSION).tar.gz"
	@ls -lh "$(CURDIR)/rimsort-$(VERSION).tar.gz"

# Build SRPM from spec file and source tarball
# Copr expects SRPM in the $(outdir) directory
.PHONY: build-srpm
build-srpm:
	@echo "==> Building SRPM"

	# Extract version from git tag (same as create-tarball)
	$(eval VERSION := $(shell git describe --tags --abbrev=0 | sed 's/^v//'))
	@echo "Building SRPM for version: $(VERSION)"

	# Build SRPM using rpmbuild
	# -bs: build source package only
	# --define "_sourcedir $(CURDIR)": look for source tarball in current directory
	# --define "_srcrpmdir $(outdir)": output SRPM to Copr's specified outdir
	# --define "version $(VERSION)": override %{version} macro in spec file
	@rpmbuild -bs "$(spec)" \
		--define "_sourcedir $(CURDIR)" \
		--define "_srcrpmdir $(outdir)" \
		--define "version $(VERSION)"

	@echo "SRPM build complete!"
	@echo "Output directory contents:"
	@ls -lh "$(outdir)"
