.PHONY: dev/lint dev/format dev/typecheck dev/test dev/build-testkit dev/check

dev/lint: require-uv
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- ruff check .

dev/format: require-uv
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- ruff format .
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- ruff check --fix .

dev/typecheck: require-uv
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- mypy

dev/test: require-uv
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- pytest

dev/build-testkit:
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- build --out-dir packages/vitalserver-testkit/dist --clear packages/vitalserver-testkit

dev/check: dev/lint dev/typecheck dev/test
