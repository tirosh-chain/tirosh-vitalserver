.PHONY: lint format typecheck test build-testkit check

lint: require-uv
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- ruff check .

format: require-uv
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- ruff format .
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- ruff check --fix .

typecheck: require-uv
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- mypy

test: require-uv
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- pytest

build-testkit:
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- build --out-dir packages/vitalserver-testkit/dist --clear packages/vitalserver-testkit

check: lint typecheck test
