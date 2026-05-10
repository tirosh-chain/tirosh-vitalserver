.PHONY: lint format typecheck test build-testkit check

lint:
	$(UV) run ruff check .

format:
	$(UV) run ruff format .
	$(UV) run ruff check --fix .

typecheck:
	$(UV) run mypy

test:
	$(UV) run pytest

build-testkit:
	$(UV) build --out-dir packages/vitalserver-testkit/dist --clear packages/vitalserver-testkit

check: lint typecheck test
