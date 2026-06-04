.DEFAULT_GOAL := help

DOCKER_COMPOSE ?= docker compose
UV ?= uv
PYTHON ?= python3
DEVTOOLS_RUNNER ?= $(if $(wildcard .venv/bin/vitalserver-devtools),.venv/bin/vitalserver-devtools,$(UV) run --project packages/vitalserver-devtools vitalserver-devtools)

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
TESTKIT_RUNNER ?= $(if $(wildcard .venv/bin/python),.venv/bin/python scripts/test_vitalserver.py,$(shell if command -v "$(UV)" >/dev/null 2>&1; then printf "%s" "$(UV) run python scripts/test_vitalserver.py"; else printf "%s" "$(PYTHON) scripts/test_vitalserver.py"; fi))
TESTKIT := $(TESTKIT_RUNNER) --config $(TESTKIT_CONFIG)
E2E_LOOP_COUNT ?= 0
E2E_LOOP_INTERVAL ?= 10
CHAOS_LOOP_COUNT ?= 5
CHAOS_LOOP_INTERVAL ?= 0

include make/submodule.mk
include make/proxy.mk
include make/env.mk
include make/compose.mk
include make/testkit.mk
include make/python.mk
include make/pwa.mk
include make/vm.mk

.PHONY: \
	dist/dmg/release dist/pkg/release dist/update/release \
	dist/update/verify/release dist/image-update/release \
	dist/image-update/verify/release dist/dmg/dev dist/pkg/dev \
	dist/update/dev dist/update/verify/dev \
	dist/image-update/dev dist/image-update/verify/dev \
	dist/install/dev dist/installed/health dist/uninstall/dev \
	runtime/up runtime/up-bridged runtime/down runtime/status runtime/health \
	runtime/prepare runtime/ip runtime/proxy/start runtime/clean \
	runtime/interfaces runtime/network/shared runtime/network/bridged runtime/e2e/smoke \
	runtime/permission/audit runtime/chaos runtime/chaos/loop runtime/coverage e2e/smoke e2e/local e2e/local/loop \
	devtools/version-source devtools/build devtools/app devtools/nginx/artifact devtools/nginx/bundle \
	devtools/docker/images devtools/sign devtools/sign/bridged devtools/bridged/preflight \
	devtools/init devtools/download devtools/cloud-init devtools/stage \
	devtools/airgap-rootfs devtools/golden-rootfs devtools/start devtools/start/detached \
	devtools/wait/ip devtools/wait/http devtools/package/clean

dist/dmg/release: internal/vm/dmg/release
dist/pkg/release: internal/vm/pkg/release
dist/update/release: internal/vm/update/release
dist/update/verify/release: internal/vm/update/verify/release
dist/image-update/release: internal/vm/image-update/release
dist/image-update/verify/release: internal/vm/image-update/verify/release
dist/dmg/dev: internal/vm/dmg/dev
dist/pkg/dev: internal/vm/pkg/dev
dist/update/dev: internal/vm/update/dev
dist/update/verify/dev: internal/vm/update/verify/dev
dist/image-update/dev: internal/vm/image-update/dev
dist/image-update/verify/dev: internal/vm/image-update/verify/dev
dist/install/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
dist/install/dev: internal/vm/pkg/install
dist/installed/health: internal/vm/installed/health
dist/uninstall/dev: internal/vm/pkg/uninstall/dev

runtime/up: internal/vm/up
runtime/up-bridged: internal/vm/up-bridged
runtime/down: internal/vm/down
runtime/status: internal/vm/status
runtime/health: internal/vm/health
runtime/prepare: internal/vm/prepare
runtime/ip: internal/vm/ip
runtime/proxy/start: internal/vm/proxy/start
runtime/clean: internal/vm/clean
runtime/interfaces: internal/vm/interfaces
runtime/network/shared: internal/vm/network/shared
runtime/network/bridged: internal/vm/network/bridged
runtime/e2e/smoke: internal/vm/e2e/smoke
runtime/permission/audit:
	$(PYTHON) scripts/runtime_permission_audit.py $(RUNTIME_PERMISSION_AUDIT_ARGS)
runtime/chaos:
	CLANG_MODULE_CACHE_PATH="$(VM_CLANG_MODULE_CACHE)" swift test --package-path "$(VM_SWIFT_PACKAGE_DIR)" --filter Chaos
runtime/chaos/loop:
	@iteration=1; \
	while :; do \
		printf "\n== runtime chaos iteration %s ==\n" "$$iteration"; \
		$(MAKE) runtime/chaos || exit $$?; \
		if [ "$(CHAOS_LOOP_COUNT)" != "0" ] && [ "$$iteration" -ge "$(CHAOS_LOOP_COUNT)" ]; then \
			break; \
		fi; \
		iteration=$$((iteration + 1)); \
		sleep "$(CHAOS_LOOP_INTERVAL)"; \
	done
runtime/coverage: internal/vm/coverage
e2e/smoke: internal/vm/e2e/smoke
e2e/local: e2e/smoke pwa/check pwa/test pwa/build

e2e/local/loop:
	@iteration=1; \
	while :; do \
		printf "\n== local e2e iteration %s ==\n" "$$iteration"; \
		$(MAKE) e2e/local || exit $$?; \
		if [ "$(E2E_LOOP_COUNT)" != "0" ] && [ "$$iteration" -ge "$(E2E_LOOP_COUNT)" ]; then \
			break; \
		fi; \
		iteration=$$((iteration + 1)); \
		sleep "$(E2E_LOOP_INTERVAL)"; \
	done

devtools/version-source: internal/vm/version-source
devtools/build: internal/vm/build
devtools/app: internal/vm/app
devtools/nginx/artifact: internal/vm/nginx/artifact
devtools/nginx/bundle: internal/vm/nginx/bundle
devtools/docker/images: internal/vm/docker/images
devtools/sign: internal/vm/sign
devtools/sign/bridged: internal/vm/sign/bridged
devtools/bridged/preflight: internal/vm/bridged/preflight
devtools/init: internal/vm/init
devtools/download: internal/vm/download
devtools/cloud-init: internal/vm/cloud-init
devtools/stage: internal/vm/stage
devtools/airgap-rootfs: internal/vm/airgap-rootfs
devtools/golden-rootfs: internal/vm/golden-rootfs
devtools/start: internal/vm/start
devtools/start/detached: internal/vm/start/detached
devtools/wait/ip: internal/vm/wait/ip
devtools/wait/http: internal/vm/wait/http
devtools/package/clean: internal/vm/pkg/clean

.PHONY: help help-run help-dist help-runtime help-devtools help-proxy help-dev help-pwa help-all
help:
	@printf "tirosh-vitalserver\n"
	@printf "\n"
	@printf "Common:\n"
	@printf "  make doctor                    Check local tools and repository setup\n"
	@printf "  make bootstrap                 Prepare .env, submodules, proxy config, and optional Python env\n"
	@printf "  make help-all                  Show every help section\n"
	@printf "\n"
	@printf "App:\n"
	@printf "  make app/up                    Start VitalServer stack through macOS host proxy\n"
	@printf "  make open                      Open VitalServer in browser\n"
	@printf "  make app/logs                  Follow logs\n"
	@printf "  make app/ps                    Show container status\n"
	@printf "  make app/down                  Stop proxy and Compose stack, keep volumes\n"
	@printf "  make swagger/up                Start Swagger UI only\n"
	@printf "\n"
	@printf "Packaging:\n"
	@printf "  make dist/pkg/dev              Build development pkg\n"
	@printf "  make dist/dmg/release          Build release installer dmg\n"
	@printf "  make dist/update/release       Build release product update bundle\n"
	@printf "  make dist/image-update/release Build release VM image/rootfs update bundle\n"
	@printf "  make dist/install/dev          Install development pkg on this Mac\n"
	@printf "\n"
	@printf "Runtime:\n"
	@printf "  make runtime/up                Start local macOS VM runtime and host proxy\n"
	@printf "  make runtime/health            Check VM, guest HTTP, and host proxy reachability\n"
	@printf "  make runtime/down              Stop local VM runtime\n"
	@printf "  make runtime/chaos             Run deterministic runtime chaos scenarios\n"
	@printf "  make runtime/permission/audit  Audit installed runtime file permissions\n"
	@printf "\n"
	@printf "Dev/Test:\n"
	@printf "  make testkit/smoke             Run bounded productization smoke scenario\n"
	@printf "  make pwa/dev                   Start Runtime Control PWA dev server\n"
	@printf "  make dev/check                 Run lint, typecheck, and test\n"
	@printf "  make e2e/smoke                 Run local Runtime Control HTTP smoke test\n"
	@printf "  make e2e/local                 Run local HTTP smoke and PWA checks\n"
	@printf "\n"
	@printf "Low-Level Build Tools:\n"
	@printf "  make devtools/golden-rootfs    Build package golden rootfs cache\n"
	@printf "  make devtools/docker/images    Build Docker image bundle\n"
	@printf "  make devtools/nginx/bundle     Build self-contained nginx bundle\n"
	@printf "\n"
	@printf "More help:\n"
	@printf "  make help-run        App, Compose, Swagger, cleanup\n"
	@printf "  make help-dist       Distribution package, install, update commands\n"
	@printf "  make help-runtime    Direct local runtime lifecycle\n"
	@printf "  make help-devtools   Low-level build and staging steps\n"
	@printf "  make help-proxy      macOS host nginx proxy\n"
	@printf "  make help-dev        Python/testkit development commands\n"
	@printf "  make help-pwa        Runtime Control PWA commands\n"
	@printf "  make help-all        Full command list\n"
	@printf "\n"
	@printf "Config:\n"
	@printf "  .env is loaded by make when present\n"
	@printf "  COMPOSE_ENV_FILE=.env.local\n"

help-run:
	@printf "tirosh-vitalserver: run\n"
	@printf "\n"
	@printf "Setup:\n"
	@printf "  make doctor          Check local tools and repository setup\n"
	@printf "  make bootstrap       Prepare .env, submodules, proxy config, and optional Python env\n"
	@printf "\n"
	@printf "App:\n"
	@printf "  make app/up          Start VitalServer stack through macOS host proxy\n"
	@printf "  make open            Open VitalServer in browser\n"
	@printf "  make app/logs        Follow logs\n"
	@printf "  make app/ps          Show container status\n"
	@printf "  make app/shell       Open a shell in the app container\n"
	@printf "  make app/restart     Restart proxy and stack\n"
	@printf "  make app/down        Stop proxy and Compose stack, keep volumes\n"
	@printf "  make app/rebuild     Rebuild and recreate the app container only\n"
	@printf "\n"
	@printf "Verify:\n"
	@printf "  make testkit/smoke   Run bounded productization smoke scenario\n"
	@printf "  make testkit/verify  Send sample data and verify UI-visible state\n"
	@printf "  make testkit/load    Run finite load scenario\n"
	@printf "  make testkit/stream  Stream sample data until interrupted\n"
	@printf "  make testkit/health  Check VitalServer health with testkit\n"
	@printf "\n"
	@printf "Tools:\n"
	@printf "  make swagger/up      Start Swagger UI only\n"
	@printf "  make swagger/down    Stop Swagger UI only, keep base stack\n"
	@printf "  make app/build       Build Compose images\n"
	@printf "  make app/config      Print resolved Docker Compose config\n"
	@printf "  make app/clean/volumes Stop proxy and Compose stack, remove volumes\n"
	@printf "  make app/clean       Remove proxy runtime, containers, volumes, orphans, and local images\n"

help-dist:
	@printf "tirosh-vitalserver: dist\n"
	@printf "\n"
	@printf "Development artifacts:\n"
	@printf "  make dist/dmg/dev      Build development installer dmg\n"
	@printf "  make dist/pkg/dev      Build development pkg\n"
	@printf "  make dist/update/dev        Build development product update bundle\n"
	@printf "  make dist/update/verify/dev Verify development product update bundle\n"
	@printf "  make dist/image-update/dev  Build development VM image/rootfs update bundle\n"
	@printf "  make dist/image-update/verify/dev Verify development VM image/rootfs update bundle\n"
	@printf "\n"
	@printf "Release artifacts:\n"
	@printf "  make dist/dmg/release      Build release installer dmg from clean golden rootfs\n"
	@printf "  make dist/pkg/release      Build release pkg from clean golden rootfs\n"
	@printf "  make dist/update/release        Build release product update bundle\n"
	@printf "  make dist/update/verify/release Verify release product update bundle\n"
	@printf "  make dist/image-update/release  Build release VM image/rootfs update bundle\n"
	@printf "  make dist/image-update/verify/release Verify release VM image/rootfs update bundle\n"
	@printf "\n"
	@printf "Install test:\n"
	@printf "  make dist/install/dev      Install the selected pkg on this Mac with sudo\n"
	@printf "  make dist/installed/health Check installed runtime and host proxy\n"
	@printf "  make dist/uninstall/dev    Remove development runtime install\n"
	@printf "\n"
	@printf "More help:\n"
	@printf "  make help-runtime    Direct local runtime lifecycle and networking\n"
	@printf "  make help-devtools   Low-level build and staging steps\n"
	@printf "\n"
	@printf "Config:\n"
	@printf "  VM_RELEASE_BRANCH=main can override the release branch guard\n"
	@printf "  VM_COMPRESSION_THREADS=<cpu-count> for faster pkg compression when pigz is installed\n"

help-runtime:
	@printf "tirosh-vitalserver: runtime\n"
	@printf "\n"
	@printf "Runtime:\n"
	@printf "  make runtime/up           Prepare runtime, start it in background, then start host proxy\n"
	@printf "  make runtime/up-bridged   Prepare and start local runtime on bridged LAN\n"
	@printf "  make runtime/down         Stop local runtime\n"
	@printf "  make runtime/status       Show local runtime process status\n"
	@printf "  make runtime/health       Check runtime IP, guest HTTP, and host proxy reachability\n"
	@printf "  make runtime/prepare      Download assets and stage guest deployment bundle\n"
	@printf "  make runtime/ip           Show detected runtime IP\n"
	@printf "  make runtime/proxy/start  Start host proxy for a runtime endpoint\n"
	@printf "  make runtime/clean        Remove runtime state, keep shared data\n"
	@printf "  make runtime/e2e/smoke    Run local Runtime Control HTTP smoke test\n"
	@printf "  make runtime/chaos        Run deterministic macOS runtime chaos scenarios\n"
	@printf "  make runtime/chaos/loop   Repeat deterministic runtime chaos scenarios\n"
	@printf "  make runtime/permission/audit  Audit installed runtime file permissions\n"
	@printf "  make runtime/coverage     Run Swift tests with source coverage report\n"
	@printf "\n"
	@printf "Networking:\n"
	@printf "  make runtime/interfaces       List bridged network interfaces\n"
	@printf "  make runtime/network/shared   Configure runtime to use shared/NAT networking\n"
	@printf "  make runtime/network/bridged  Configure runtime to use bridged networking\n"

help-devtools:
	@printf "tirosh-vitalserver: devtools\n"
	@printf "\n"
	@printf "Build:\n"
	@printf "  make devtools/build          Build Apple Virtualization runtime launcher\n"
	@printf "  make devtools/nginx/artifact Copy source nginx binary into local artifact cache\n"
	@printf "  make devtools/nginx/bundle   Build self-contained nginx bundle for dist pkg\n"
	@printf "  make devtools/docker/images  Build Docker image bundle for air-gapped dist pkg\n"
	@printf "  make devtools/sign           Ad-hoc sign runtime launcher with shared networking entitlement\n"
	@printf "  make devtools/sign/bridged   Sign runtime launcher with bridged networking entitlement and real identity\n"
	@printf "  make devtools/bridged/preflight Check bridged signing prerequisites\n"
	@printf "  make devtools/init           Initialize local runtime config only\n"
	@printf "  make devtools/download       Download Ubuntu boot assets only\n"
	@printf "  make devtools/cloud-init     Create local cloud-init seed image only\n"
	@printf "  make devtools/stage          Stage guest deployment bundle only\n"
	@printf "  make devtools/airgap-rootfs  Prepare rootfs with guest packages for offline install\n"
	@printf "  make devtools/golden-rootfs  Build package golden rootfs cache\n"
	@printf "  make devtools/start          Start runtime in foreground with serial console\n"
	@printf "  make devtools/start/detached Start runtime in background\n"
	@printf "  make devtools/wait/ip        Wait until guest writes its runtime IP\n"
	@printf "  make devtools/wait/http      Wait until guest HTTP returns 2xx/3xx\n"
	@printf "  make devtools/package/clean  Remove dist pkg build artifacts\n"
	@printf "\n"
	@printf "Config:\n"
	@printf "  VM_COMPRESSION_THREADS=<cpu-count> for faster pkg compression when pigz is installed\n"

help-proxy:
	@printf "tirosh-vitalserver: proxy\n"
	@printf "\n"
	@printf "Proxy:\n"
	@printf "  make proxy/status    Show macOS host nginx proxy status\n"
	@printf "  make proxy/config    Render macOS host nginx proxy config\n"
	@printf "  make proxy/plist     Render macOS launchd plist for host nginx proxy\n"
	@printf "  make proxy/start     Start macOS host nginx proxy only\n"
	@printf "  make proxy/stop      Stop macOS host nginx proxy only\n"
	@printf "  make proxy/reload    Reload macOS host nginx proxy config\n"
	@printf "  make proxy/stop-orphans  Stop nginx listeners left on the proxy port\n"
	@printf "  make proxy/clean     Stop proxy and remove local proxy runtime files\n"
	@printf "\n"
	@printf "Config:\n"
	@printf "  VITALSERVER_PROXY_PORT=%s\n" "$(VITALSERVER_PROXY_PORT)"
	@printf "  VITALSERVER_BIND_HOST=%s\n" "$(VITALSERVER_BIND_HOST)"
	@printf "  VITALSERVER_HTTP_PORT=%s\n" "$(VITALSERVER_HTTP_PORT)"

help-dev:
	@printf "tirosh-vitalserver: dev\n"
	@printf "\n"
	@printf "Develop:\n"
	@printf "  make dev/lint        Run Ruff checks\n"
	@printf "  make dev/format      Format Python code\n"
	@printf "  make dev/typecheck   Run mypy\n"
	@printf "  make dev/test        Run pytest\n"
	@printf "  make dev/build-testkit Build vitalserver-testkit wheel and sdist\n"
	@printf "  make dev/check       Run lint, typecheck, and test\n"
	@printf "  make testkit/install-release Install released testkit wheel without uv\n"
	@printf "\n"
	@printf "Repository:\n"
	@printf "  make repo/init       Initialize git submodules\n"
	@printf "  make repo/update-submodule Update vendor/vitalserver submodule\n"
	@printf "  make app/build       Build all Compose images\n"
	@printf "\n"
	@printf "Config:\n"
	@printf "  TESTKIT_CONFIG=%s\n" "$(TESTKIT_CONFIG)"
	@printf "  TESTKIT_VERSION=%s\n" "$(TESTKIT_VERSION)"

help-pwa:
	@printf "tirosh-vitalserver: pwa\n"
	@printf "\n"
	@printf "Runtime Control PWA:\n"
	@printf "  make pwa/install      Install PWA npm dependencies\n"
	@printf "  make pwa/generate-api Generate OpenAPI TypeScript types\n"
	@printf "  make pwa/check        Typecheck Runtime Control PWA\n"
	@printf "  make pwa/test         Run Runtime Control PWA tests\n"
	@printf "  make pwa/coverage     Run Runtime Control PWA coverage report\n"
	@printf "  make pwa/build        Build Runtime Control PWA static assets\n"
	@printf "  make pwa/dev          Start Vite dev server on 127.0.0.1:5174\n"
	@printf "  make pwa/preview      Preview built PWA on 127.0.0.1:4174\n"
	@printf "\n"
	@printf "Config:\n"
	@printf "  PWA_DIR=%s\n" "$(PWA_DIR)"

help-all:
	@$(MAKE) --no-print-directory help-run
	@printf "\n"
	@$(MAKE) --no-print-directory help-dist
	@printf "\n"
	@$(MAKE) --no-print-directory help-runtime
	@printf "\n"
	@$(MAKE) --no-print-directory help-devtools
	@printf "\n"
	@$(MAKE) --no-print-directory help-proxy
	@printf "\n"
	@$(MAKE) --no-print-directory help-dev
	@printf "\n"
	@$(MAKE) --no-print-directory help-pwa
