.DEFAULT_GOAL := help

DOCKER_COMPOSE ?= docker compose
UV ?= uv

COMPOSE_ENV_FILE ?=
TESTKIT_CONFIG ?= config/testkit.toml

COMPOSE := $(strip $(DOCKER_COMPOSE) $(if $(COMPOSE_ENV_FILE),--env-file $(COMPOSE_ENV_FILE),))
TESTKIT := $(UV) run python scripts/test_vitalserver.py --config $(TESTKIT_CONFIG)

include make/submodule.mk
include make/env.mk
include make/compose.mk
include make/testkit.mk
include make/python.mk

.PHONY: help
help:
	@printf "tirosh-vitalserver\n"
	@printf "\n"
	@printf "Run:\n"
	@printf "  make doctor          Check local tools and repository setup\n"
	@printf "  make bootstrap       Initialize submodules and sync Python env when uv exists\n"
	@printf "  make up              Start VitalServer stack\n"
	@printf "  make down            Stop stack and keep volumes\n"
	@printf "  make restart         Restart stack\n"
	@printf "  make logs            Follow logs\n"
	@printf "  make ps              Show container status\n"
	@printf "  make swagger         Start Swagger UI\n"
	@printf "\n"
	@printf "Verify:\n"
	@printf "  make testkit-smoke   Run bounded productization smoke scenario\n"
	@printf "  make testkit-verify  Send sample data and verify UI-visible state\n"
	@printf "  make testkit-load    Run finite load scenario\n"
	@printf "  make testkit-stream  Stream sample data until interrupted\n"
	@printf "\n"
	@printf "Develop:\n"
	@printf "  make lint            Run Ruff checks\n"
	@printf "  make format          Format Python code\n"
	@printf "  make typecheck       Run mypy\n"
	@printf "  make test            Run pytest\n"
	@printf "  make build-testkit   Build vitalserver-testkit wheel and sdist\n"
	@printf "  make check           Run lint, typecheck, and test\n"
	@printf "\n"
	@printf "Config:\n"
	@printf "  TESTKIT_CONFIG=config/testkit.toml\n"
	@printf "  COMPOSE_ENV_FILE=.env.local\n"
