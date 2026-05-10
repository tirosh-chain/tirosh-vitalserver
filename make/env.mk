.PHONY: bootstrap doctor require-uv

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
		printf "optional missing: uv; Docker runtime works, Python testkit does not\n"; \
	fi

require-uv:
	@command -v "$(UV)" >/dev/null 2>&1 || { \
		printf "missing: uv\n"; \
		printf "Install uv to run Python testkit and developer checks.\n"; \
		printf "See https://docs.astral.sh/uv/getting-started/installation/\n"; \
		exit 127; \
	}
