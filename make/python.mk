.PHONY: lint format typecheck test check

lint: require-uv
	$(UV) run ruff check .

format: require-uv
	$(UV) run ruff format .
	$(UV) run ruff check --fix .

typecheck: require-uv
	$(UV) run mypy

test: require-uv
	$(UV) run pytest

check: lint typecheck test
