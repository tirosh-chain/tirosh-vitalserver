.PHONY: lint format typecheck test build-testkit check

lint: require-uv
	$(UV) run ruff check .

format: require-uv
	$(UV) run ruff format .
	$(UV) run ruff check --fix .

typecheck: require-uv
	$(UV) run mypy

test: require-uv
	$(UV) run pytest

build-testkit:
	$(UV) build --out-dir packages/vitalserver-testkit/dist --clear packages/vitalserver-testkit

check: lint typecheck test
