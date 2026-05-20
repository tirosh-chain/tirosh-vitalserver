.DEFAULT_GOAL := help

DOCKER_COMPOSE ?= docker compose
UV ?= uv
PYTHON ?= python3

COMPOSE_ENV_FILE ?=
TESTKIT_CONFIG ?= config/testkit.toml
TESTKIT_VERSION ?= 0.1.1
TESTKIT_RELEASE_TAG ?= testkit-v$(TESTKIT_VERSION)
TESTKIT_RELEASE_DIR ?= .tmp/testkit-release

-include .env
-include $(COMPOSE_ENV_FILE)

VITALSERVER_PROXY_PORT ?= 80
VITALSERVER_BIND_HOST ?= 127.0.0.1
VITALSERVER_HTTP_PORT ?= 18080
VITALSERVER_REDIS_HOST ?= redis
VITALSERVER_REDIS_PORT ?= 6379
VITALSERVER_TRUST_PROXY ?= 1

COMPOSE := $(strip $(DOCKER_COMPOSE) $(if $(COMPOSE_ENV_FILE),--env-file $(COMPOSE_ENV_FILE),))
TESTKIT_RUNNER ?= $(shell if command -v "$(UV)" >/dev/null 2>&1; then printf "%s" "$(UV) run python scripts/test_vitalserver.py"; else printf "%s" "$(PYTHON) scripts/test_vitalserver.py"; fi)
TESTKIT := $(TESTKIT_RUNNER) --config $(TESTKIT_CONFIG)

include make/submodule.mk
include make/env.mk
include make/compose.mk
include make/proxy.mk
include make/testkit.mk
include make/python.mk
include make/vm.mk

.PHONY: help
help:
	@printf "tirosh-vitalserver\n"
	@printf "\n"
	@printf "Core:\n"
	@printf "  make up              Start VitalServer stack through macOS host proxy\n"
	@printf "  make open            Open VitalServer in browser\n"
	@printf "  make logs            Follow logs\n"
	@printf "  make ps              Show container status\n"
	@printf "  make restart         Restart proxy and stack\n"
	@printf "  make down            Stop proxy and Compose stack, keep volumes\n"
	@printf "  make app-rebuild     Rebuild and recreate the app container only\n"
	@printf "\n"
	@printf "Setup:\n"
	@printf "  make doctor          Check local tools and repository setup\n"
	@printf "  make bootstrap       Prepare .env, submodules, proxy config, and optional Python env\n"
	@printf "\n"
	@printf "Proxy:\n"
	@printf "  make proxy-status    Show macOS host nginx proxy status\n"
	@printf "  make proxy-config    Render macOS host nginx proxy config\n"
	@printf "  make proxy-plist     Render macOS launchd plist for host nginx proxy\n"
	@printf "  make proxy-start     Start macOS host nginx proxy only\n"
	@printf "  make proxy-stop      Stop macOS host nginx proxy only\n"
	@printf "  make proxy-clean     Stop proxy and remove local proxy runtime files\n"
	@printf "  make proxy-reload    Reload macOS host nginx proxy config\n"
	@printf "\n"
	@printf "VM PoC:\n"
	@printf "  make vm-up           Prepare and start Linux VM PoC\n"
	@printf "  make vm-down         Stop Linux VM PoC\n"
	@printf "  make vm-status       Show Linux VM PoC process status\n"
	@printf "  make vm-prepare      Download Linux assets and stage guest deployment bundle\n"
	@printf "  make vm-clean        Remove VM runtime state, keep shared data\n"
	@printf "\n"
	@printf "Tools:\n"
	@printf "  make swagger         Start Swagger UI only\n"
	@printf "  make swagger-down    Stop Swagger UI only, keep base stack\n"
	@printf "  make app-build       Build the app image only\n"
	@printf "  make clean-volumes   Stop proxy and Compose stack, remove volumes\n"
	@printf "  make clean           Remove proxy runtime, containers, volumes, orphans, and local images\n"
	@printf "  make install-testkit-release  Install released testkit wheel without uv\n"
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
	@printf "  make vm-build        Build Apple Virtualization VM launcher\n"
	@printf "  make vm-sign         Ad-hoc sign VM launcher with shared networking entitlement\n"
	@printf "  make vm-sign-bridged Sign VM launcher with bridged networking entitlement\n"
	@printf "  make vm-init         Initialize VM runtime config only\n"
	@printf "  make vm-download     Download Ubuntu boot assets only\n"
	@printf "  make vm-stage        Stage guest deployment bundle only\n"
	@printf "  make vm-interfaces   List bridged network interfaces\n"
	@printf "\n"
	@printf "Config:\n"
	@printf "  .env is loaded by make when present\n"
	@printf "  TESTKIT_CONFIG=config/testkit.toml\n"
	@printf "  TESTKIT_VERSION=0.1.1\n"
	@printf "  COMPOSE_ENV_FILE=.env.local\n"
