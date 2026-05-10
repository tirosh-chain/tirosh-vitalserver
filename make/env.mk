.PHONY: bootstrap doctor install-testkit-release require-testkit-runtime require-uv

bootstrap: init
	@if command -v "$(UV)" >/dev/null 2>&1; then \
		printf "Syncing Python workspace with %s\n" "$(UV)"; \
		"$(UV)" sync; \
	else \
		printf "uv not found; skipping Python workspace sync.\n"; \
		printf "Install uv only when you need testkit, lint, typecheck, or pytest.\n"; \
	fi

doctor:
	@printf "Checking local environment\n"
	@command -v git >/dev/null 2>&1 || { printf "missing: git\n"; exit 1; }
	@printf "ok: git\n"
	@command -v docker >/dev/null 2>&1 || { printf "missing: docker\n"; exit 1; }
	@printf "ok: docker\n"
	@docker compose version >/dev/null 2>&1 || { printf "missing: Docker Compose v2\n"; exit 1; }
	@printf "ok: Docker Compose v2\n"
	@if [ -e vendor/vitalserver/.git ]; then \
		printf "ok: vendor/vitalserver submodule\n"; \
	else \
		printf "missing: vendor/vitalserver submodule; run 'make init'\n"; \
	fi
	@if command -v "$(UV)" >/dev/null 2>&1; then \
		printf "ok: uv\n"; \
	else \
		printf "optional missing: uv; checking installed testkit package\n"; \
		"$(PYTHON)" -c "import pydantic_settings, tirosh_vitalserver.testkit" >/dev/null 2>&1 \
			&& printf "ok: installed testkit runtime\n" \
			|| printf "optional missing: installed testkit runtime; run 'make install-testkit-release'\n"; \
	fi

install-testkit-release:
	@command -v gh >/dev/null 2>&1 || { \
		printf "missing: gh\n"; \
		printf "Install GitHub CLI and run 'gh auth login', or download the wheel from GitHub Release manually.\n"; \
		exit 127; \
	}
	@command -v "$(PYTHON)" >/dev/null 2>&1 || { printf "missing: $(PYTHON)\n"; exit 127; }
	@mkdir -p "$(TESTKIT_RELEASE_DIR)"
	@gh release download "$(TESTKIT_RELEASE_TAG)" \
		--repo tirosh-chain/tirosh-vitalserver \
		--pattern "*.whl" \
		--dir "$(TESTKIT_RELEASE_DIR)" \
		--clobber
	@wheel=$$(ls "$(TESTKIT_RELEASE_DIR)"/tirosh_vitalserver_testkit-$(TESTKIT_VERSION)-*.whl | head -n 1); \
		printf "Installing %s with %s\n" "$$wheel" "$(PYTHON)"; \
		"$(PYTHON)" -m pip install --upgrade "$$wheel" pydantic-settings

require-testkit-runtime:
	@if command -v "$(UV)" >/dev/null 2>&1; then \
		exit 0; \
	fi
	@command -v "$(PYTHON)" >/dev/null 2>&1 || { printf "missing: $(PYTHON)\n"; exit 127; }
	@"$(PYTHON)" -c "import pydantic_settings, tirosh_vitalserver.testkit" >/dev/null 2>&1 || { \
		printf "missing: installed testkit runtime\n"; \
		printf "Run 'make install-testkit-release' or install uv for workspace execution.\n"; \
		exit 127; \
	}

require-uv:
	@command -v "$(UV)" >/dev/null 2>&1 || { \
		printf "missing: uv\n"; \
		printf "Install uv to run Python testkit and developer checks.\n"; \
		printf "See https://docs.astral.sh/uv/getting-started/installation/\n"; \
		exit 127; \
	}
