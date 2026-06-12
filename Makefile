.DEFAULT_GOAL := help

DOCKER_COMPOSE ?= docker compose
UV ?= uv
PYTHON ?= python3
DEVTOOLS_RUNNER ?= $(if $(wildcard .venv/bin/vitalserver-devtools),.venv/bin/vitalserver-devtools,$(UV) run --project packages/vitalserver-devtools vitalserver-devtools)
DOCS_HOST ?= 127.0.0.1
DOCS_PORT ?= 8000
DOCS_PORT_MAX ?= 8100

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
	dist/image-update/verify/release dist/dmg/dev dist/dmg/dev/compile dist/pkg/dev dist/pkg/dev/compile \
	dist/update/dev dist/update/verify/dev \
	dist/image-update/dev dist/image-update/verify/dev \
	dist/reset-installer/dev dist/reset-installer/release \
	dist/install/dev dist/installed/health dist/uninstall/dev \
	runtime/up runtime/up-bridged runtime/down runtime/status runtime/health \
	runtime/prepare runtime/ip runtime/proxy/start runtime/clean \
	runtime/interfaces runtime/network/shared runtime/network/bridged runtime/e2e/smoke \
	runtime/permission/audit runtime/chaos runtime/chaos/loop runtime/coverage e2e/smoke e2e/local e2e/local/loop \
	docs/build docs/serve \
	devtools/version-source devtools/build devtools/app devtools/nginx/artifact devtools/nginx/bundle \
	devtools/docker/images devtools/sign devtools/sign/bridged devtools/bridged/preflight \
	devtools/init devtools/download devtools/cloud-init devtools/stage \
	devtools/airgap-rootfs devtools/golden-rootfs devtools/golden-rootfs/compile devtools/golden-rootfs/runtime-smoke devtools/start devtools/start/detached \
	devtools/golden-rootfs/negative \
	devtools/wait/ip devtools/wait/http devtools/package/clean

dist/dmg/release: internal/vm/dmg/release
dist/pkg/release: internal/vm/pkg/release
dist/update/release: internal/vm/update/release
dist/update/verify/release: internal/vm/update/verify/release
dist/image-update/release: internal/vm/image-update/release
dist/image-update/verify/release: internal/vm/image-update/verify/release
dist/dmg/dev: internal/vm/dmg/dev
dist/dmg/dev/compile: internal/vm/dmg/dev/compile
dist/pkg/dev: internal/vm/pkg/dev
dist/pkg/dev/compile: internal/vm/pkg/dev/compile
dist/update/dev: internal/vm/update/dev
dist/update/verify/dev: internal/vm/update/verify/dev
dist/image-update/dev: internal/vm/image-update/dev
dist/image-update/verify/dev: internal/vm/image-update/verify/dev
dist/reset-installer/dev: internal/vm/reset-installer/dev
dist/reset-installer/release: internal/vm/reset-installer/release
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

docs/build:
	$(UV) run --group docs mkdocs build

docs/serve:
	@port="$$($(PYTHON) scripts/find_free_port.py "$(DOCS_HOST)" "$(DOCS_PORT)" "$(DOCS_PORT_MAX)")" || exit $$?; \
	printf "Serving docs at http://$(DOCS_HOST):%s\n" "$$port"; \
	$(UV) run --group docs mkdocs serve --dev-addr "$(DOCS_HOST):$$port"

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
devtools/golden-rootfs/compile: internal/vm/golden-rootfs/compile
devtools/golden-rootfs/negative: internal/vm/golden-rootfs/negative
devtools/golden-rootfs/runtime-smoke: internal/vm/golden-rootfs/runtime-smoke
devtools/start: internal/vm/start
devtools/start/detached: internal/vm/start/detached
devtools/wait/ip: internal/vm/wait/ip
devtools/wait/http: internal/vm/wait/http
devtools/package/clean: internal/vm/pkg/clean

.PHONY: help help/compose help/dist help/runtime help/devtools help/proxy help/dev help/pwa help/docs help/all
help:
	@printf "NAME\n"
	@printf "  tirosh-vitalserver - repository, compose sandbox, runtime, and distribution targets\n"
	@printf "\n"
	@printf "SYNOPSIS\n"
	@printf "  make [TARGET] [VAR=value]...\n"
	@printf "  make help/{compose|runtime|dist|pwa|docs|dev|devtools|proxy|all}\n"
	@printf "\n"
	@printf "COMMON TARGETS\n"
	@printf "  dev/doctor      Check local developer tools and repository setup\n"
	@printf "  dev/bootstrap   Prepare .env, submodules, proxy config, and optional Python env\n"
	@printf "  compose/up      Start the Compose productization sandbox through host proxy\n"
	@printf "  runtime/up      Start local macOS VM runtime and host proxy\n"
	@printf "  docs/serve      Serve MkDocs site with automatic port fallback\n"
	@printf "  dist/pkg/dev    Build development pkg\n"
	@printf "\n"
	@printf "HELP TOPICS\n"
	@printf "  help/compose    Compose sandbox, Swagger, testkit, cleanup\n"
	@printf "  help/runtime    Direct local runtime lifecycle\n"
	@printf "  help/dist       Distribution package, install, update commands\n"
	@printf "  help/pwa        Runtime Control PWA commands\n"
	@printf "  help/docs       Documentation site commands\n"
	@printf "  help/dev        Repository and Python development commands\n"
	@printf "  help/devtools   Low-level build and staging steps\n"
	@printf "  help/proxy      macOS host nginx proxy\n"
	@printf "  help/all        Full command list\n"
	@printf "\n"
	@printf "FILES\n"
	@printf "  .env            Loaded by make when present\n"
	@printf "\n"
	@printf "VARIABLES\n"
	@printf "  COMPOSE_ENV_FILE=.env.local\n"

help/compose:
	@printf "NAME\n"
	@printf "  tirosh-vitalserver-compose - Compose productization sandbox, Swagger, and testkit targets\n"
	@printf "\n"
	@printf "SYNOPSIS\n"
	@printf "  make compose/{up|logs|ps|shell|restart|down|rebuild|build|config|clean|clean/volumes|open}\n"
	@printf "  make swagger/{up|down}\n"
	@printf "  make testkit/{smoke|verify|load|stream|health}\n"
	@printf "\n"
	@printf "COMPOSE TARGETS\n"
	@printf "  compose/up             Start Compose sandbox through macOS host proxy\n"
	@printf "  compose/open           Open VitalServer in browser\n"
	@printf "  compose/logs           Follow logs\n"
	@printf "  compose/ps             Show container status\n"
	@printf "  compose/shell          Open a shell in the app container\n"
	@printf "  compose/restart        Restart proxy and stack\n"
	@printf "  compose/down           Stop proxy and Compose stack, keep volumes\n"
	@printf "  compose/rebuild        Rebuild and recreate the app container only\n"
	@printf "  compose/build          Build Compose images\n"
	@printf "  compose/config         Print resolved Docker Compose config\n"
	@printf "  compose/clean/volumes  Stop proxy and Compose stack, remove volumes\n"
	@printf "  compose/clean          Remove proxy runtime, containers, volumes, orphans, and local images\n"
	@printf "\n"
	@printf "VERIFY TARGETS\n"
	@printf "  testkit/smoke          Run bounded productization smoke scenario\n"
	@printf "  testkit/verify         Send sample data and verify UI-visible state\n"
	@printf "  testkit/load           Run finite load scenario\n"
	@printf "  testkit/stream         Stream sample data until interrupted\n"
	@printf "  testkit/health         Check VitalServer health with testkit\n"
	@printf "\n"
	@printf "TOOL TARGETS\n"
	@printf "  swagger/up             Start Swagger UI only\n"
	@printf "  swagger/down           Stop Swagger UI only, keep base stack\n"
help/dist:
	@printf "NAME\n"
	@printf "  tirosh-vitalserver-dist - distribution package, install, and update targets\n"
	@printf "\n"
	@printf "SYNOPSIS\n"
	@printf "  make dist/{pkg|dmg|update|image-update}/{dev|release} [VM_RELEASE_BRANCH=main]\n"
	@printf "  make dist/{pkg|dmg}/dev/compile\n"
	@printf "  make dist/reset-installer/{dev|release}\n"
	@printf "  make dist/{update|image-update}/verify/{dev|release}\n"
	@printf "  make dist/{install|uninstall}/dev [VM_UNINSTALL_ARGS=--clean]\n"
	@printf "  make dist/installed/health\n"
	@printf "\n"
	@printf "ARTIFACT TARGETS\n"
	@printf "  dist/pkg/dev                  Build development pkg\n"
	@printf "  dist/pkg/dev/compile          Build development pkg and recompile the VM golden rootfs\n"
	@printf "  dist/pkg/release              Build release pkg from clean golden rootfs\n"
	@printf "  dist/dmg/dev                  Build development installer dmg\n"
	@printf "  dist/dmg/dev/compile          Build development dmg and recompile the VM golden rootfs\n"
	@printf "  dist/dmg/release              Build release installer dmg from clean golden rootfs\n"
	@printf "  dist/update/dev               Build development product update bundle\n"
	@printf "  dist/update/release           Build release product update bundle\n"
	@printf "  dist/image-update/dev         Build development VM image/rootfs update bundle\n"
	@printf "  dist/image-update/release     Build release VM image/rootfs update bundle\n"
	@printf "  dist/reset-installer/dev      Build development Reset for Reinstall pkg\n"
	@printf "  dist/reset-installer/release\n"
	@printf "                                Build release Reset for Reinstall pkg\n"
	@printf "\n"
	@printf "VERIFY TARGETS\n"
	@printf "  dist/update/verify/dev        Verify development product update bundle\n"
	@printf "  dist/update/verify/release    Verify release product update bundle\n"
	@printf "  dist/image-update/verify/dev  Verify development VM image/rootfs update bundle\n"
	@printf "  dist/image-update/verify/release\n"
	@printf "                                Verify release VM image/rootfs update bundle\n"
	@printf "\n"
	@printf "INSTALL TARGETS\n"
	@printf "  dist/install/dev              Install the selected pkg on this Mac with sudo\n"
	@printf "  dist/installed/health         Check installed runtime and host proxy\n"
	@printf "  dist/uninstall/dev            Remove development runtime install\n"
	@printf "\n"
	@printf "VARIABLES\n"
	@printf "  VM_RELEASE_BRANCH=main        Override the release branch guard\n"
	@printf "  VM_COMPRESSION_THREADS=N      Use pigz with N compression threads when available\n"
	@printf "  VM_CODESIGN_IDENTITY=-        Codesign identity for local unsigned/dev artifacts\n"
	@printf "  VM_NGINX_BIN=/path/nginx      Use a prepared nginx artifact instead of source binary\n"
	@printf "  VM_UNINSTALL_ARGS=--clean     Run development uninstall in clean mode\n"
	@printf "\n"
	@printf "PROFILE TARGETS\n"
	@printf "  Use dist/{pkg|dmg}/dev/compile for VM compile builds.\n"

help/runtime:
	@printf "NAME\n"
	@printf "  tirosh-vitalserver-runtime - direct local macOS VM runtime lifecycle targets\n"
	@printf "\n"
	@printf "SYNOPSIS\n"
	@printf "  make runtime/{up|up-bridged|down|status|health|prepare|ip|clean|coverage}\n"
	@printf "  make runtime/{interfaces|network/shared|network/bridged}\n"
	@printf "  make runtime/{proxy/start|e2e/smoke|chaos|chaos/loop|permission/audit}\n"
	@printf "\n"
	@printf "RUNTIME TARGETS\n"
	@printf "  runtime/up                    Prepare runtime, start it in background, then start host proxy\n"
	@printf "  runtime/up-bridged            Prepare and start local runtime on bridged LAN\n"
	@printf "  runtime/down                  Stop local runtime\n"
	@printf "  runtime/status                Show local runtime process status\n"
	@printf "  runtime/health                Check runtime IP, guest HTTP, and host proxy reachability\n"
	@printf "  runtime/prepare               Download assets and stage guest deployment bundle\n"
	@printf "  runtime/ip                    Show detected runtime IP\n"
	@printf "  runtime/proxy/start           Start host proxy for a runtime endpoint\n"
	@printf "  runtime/clean                 Remove runtime state, keep shared data\n"
	@printf "  runtime/e2e/smoke             Run local Runtime Control HTTP smoke test\n"
	@printf "  runtime/chaos                 Run deterministic macOS runtime chaos scenarios\n"
	@printf "  runtime/chaos/loop            Repeat deterministic runtime chaos scenarios\n"
	@printf "  runtime/permission/audit      Audit installed runtime file permissions\n"
	@printf "  runtime/coverage              Run Swift tests with source coverage report\n"
	@printf "\n"
	@printf "NETWORK TARGETS\n"
	@printf "  runtime/interfaces            List bridged network interfaces\n"
	@printf "  runtime/network/shared        Configure runtime to use shared/NAT networking\n"
	@printf "  runtime/network/bridged       Configure runtime to use bridged networking\n"

help/devtools:
	@printf "NAME\n"
	@printf "  tirosh-vitalserver-devtools - low-level build and staging targets\n"
	@printf "\n"
	@printf "SYNOPSIS\n"
	@printf "  make devtools/{version-source|build|app|init|download|cloud-init|stage}\n"
	@printf "  make devtools/{airgap-rootfs|golden-rootfs|golden-rootfs/compile|start|start/detached}\n"
	@printf "  make devtools/nginx/{artifact|bundle}\n"
	@printf "  make devtools/docker/images\n"
	@printf "  make devtools/{sign|sign/bridged|bridged/preflight|wait/ip|wait/http|package/clean}\n"
	@printf "\n"
	@printf "BUILD TARGETS\n"
	@printf "  devtools/version-source       Write release version source\n"
	@printf "  devtools/build                Build Apple Virtualization runtime launcher\n"
	@printf "  devtools/app                  Build macOS Helper app\n"
	@printf "  devtools/nginx/artifact       Copy source nginx binary into local artifact cache\n"
	@printf "  devtools/nginx/bundle         Build self-contained nginx bundle for dist pkg\n"
	@printf "  devtools/docker/images        Build Docker image bundle for air-gapped dist pkg\n"
	@printf "  devtools/sign                 Ad-hoc sign runtime launcher with shared networking entitlement\n"
	@printf "  devtools/sign/bridged         Sign runtime launcher with bridged networking entitlement and real identity\n"
	@printf "  devtools/bridged/preflight    Check bridged signing prerequisites\n"
	@printf "\n"
	@printf "STAGING TARGETS\n"
	@printf "  devtools/init                 Initialize local runtime config only\n"
	@printf "  devtools/download             Download Ubuntu boot assets only\n"
	@printf "  devtools/cloud-init           Create local cloud-init seed image only\n"
	@printf "  devtools/stage                Stage guest deployment bundle only\n"
	@printf "  devtools/airgap-rootfs        Prepare rootfs with guest packages for offline install\n"
	@printf "  devtools/golden-rootfs        Build package golden rootfs cache\n"
	@printf "  devtools/golden-rootfs/compile\n"
	@printf "                                Recompile package golden rootfs cache from scratch\n"
	@printf "  devtools/start                Start runtime in foreground with serial console\n"
	@printf "  devtools/start/detached       Start runtime in background\n"
	@printf "  devtools/wait/ip              Wait until guest writes its runtime IP\n"
	@printf "  devtools/wait/http            Wait until guest HTTP returns 2xx/3xx\n"
	@printf "  devtools/package/clean        Remove dist pkg build artifacts\n"
	@printf "\n"
	@printf "VARIABLES\n"
	@printf "  VM_COMPRESSION_THREADS=N      Use pigz with N compression threads when available\n"
	@printf "  VM_ROOTFS_READY_TIMEOUT=300   Diagnostic wait timeout for rootfs compile proof\n"
	@printf "  VM_ROOTFS_SMOKE_FAIL_STAGE=x  Diagnostic fault injection for golden rootfs negative tests\n"

help/proxy:
	@printf "NAME\n"
	@printf "  tirosh-vitalserver-proxy - macOS host nginx proxy targets\n"
	@printf "\n"
	@printf "SYNOPSIS\n"
	@printf "  make proxy/{status|config|config/write|test|plist|start|run|port-check}\n"
	@printf "  make proxy/{stop|reload|stop-orphans|clean}\n"
	@printf "\n"
	@printf "PROXY TARGETS\n"
	@printf "  proxy/status                  Show macOS host nginx proxy status\n"
	@printf "  proxy/config                  Render macOS host nginx proxy config\n"
	@printf "  proxy/config/write            Write macOS host nginx proxy config\n"
	@printf "  proxy/test                    Validate macOS host nginx proxy config\n"
	@printf "  proxy/plist                   Render macOS launchd plist for host nginx proxy\n"
	@printf "  proxy/start                   Start macOS host nginx proxy only\n"
	@printf "  proxy/run                     Start macOS host nginx proxy only\n"
	@printf "  proxy/port-check              Check whether the proxy port is available\n"
	@printf "  proxy/stop                    Stop macOS host nginx proxy only\n"
	@printf "  proxy/reload                  Reload macOS host nginx proxy config\n"
	@printf "  proxy/stop-orphans            Stop nginx listeners left on the proxy port\n"
	@printf "  proxy/clean                   Stop proxy and remove local proxy runtime files\n"
	@printf "\n"
	@printf "VARIABLES\n"
	@printf "  VITALSERVER_PROXY_PORT=%s\n" "$(VITALSERVER_PROXY_PORT)"
	@printf "  VITALSERVER_BIND_HOST=%s\n" "$(VITALSERVER_BIND_HOST)"
	@printf "  VITALSERVER_HTTP_PORT=%s\n" "$(VITALSERVER_HTTP_PORT)"

help/dev:
	@printf "NAME\n"
	@printf "  tirosh-vitalserver-dev - repository setup, Python, and developer checks\n"
	@printf "\n"
	@printf "SYNOPSIS\n"
	@printf "  make dev/{doctor|bootstrap|lint|format|typecheck|test|build-testkit|check}\n"
	@printf "  make repo/{init|update-submodule}\n"
	@printf "  make {testkit/install-release|compose/build}\n"
	@printf "\n"
	@printf "DEVELOPMENT TARGETS\n"
	@printf "  dev/doctor                    Check local developer tools and repository setup\n"
	@printf "  dev/bootstrap                 Prepare .env, submodules, proxy config, and optional Python env\n"
	@printf "  dev/lint                      Run Ruff checks\n"
	@printf "  dev/format                    Format Python code\n"
	@printf "  dev/typecheck                 Run mypy\n"
	@printf "  dev/test                      Run pytest\n"
	@printf "  dev/build-testkit             Build vitalserver-testkit wheel and sdist\n"
	@printf "  dev/check                     Run lint, typecheck, and test\n"
	@printf "  testkit/install-release       Install released testkit wheel without uv\n"
	@printf "\n"
	@printf "REPOSITORY TARGETS\n"
	@printf "  repo/init                     Initialize git submodules\n"
	@printf "  repo/update-submodule         Update vendor/vitalserver submodule\n"
	@printf "  compose/build                 Build all Compose images\n"
	@printf "\n"
	@printf "VARIABLES\n"
	@printf "  TESTKIT_CONFIG=%s\n" "$(TESTKIT_CONFIG)"
	@printf "  TESTKIT_VERSION=%s\n" "$(TESTKIT_VERSION)"

help/pwa:
	@printf "NAME\n"
	@printf "  tirosh-vitalserver-pwa - Runtime Control PWA targets\n"
	@printf "\n"
	@printf "SYNOPSIS\n"
	@printf "  make pwa/{install|generate-api|check|test|coverage|build|dev|preview}\n"
	@printf "\n"
	@printf "PWA TARGETS\n"
	@printf "  pwa/install                   Install PWA npm dependencies\n"
	@printf "  pwa/generate-api              Generate OpenAPI TypeScript types\n"
	@printf "  pwa/check                     Typecheck Runtime Control PWA\n"
	@printf "  pwa/test                      Run Runtime Control PWA tests\n"
	@printf "  pwa/coverage                  Run Runtime Control PWA coverage report\n"
	@printf "  pwa/build                     Build Runtime Control PWA static assets\n"
	@printf "  pwa/dev                       Start Vite dev server on 127.0.0.1:5174\n"
	@printf "  pwa/preview                   Preview built PWA on 127.0.0.1:4174\n"
	@printf "\n"
	@printf "VARIABLES\n"
	@printf "  PWA_DIR=%s\n" "$(PWA_DIR)"

help/docs:
	@printf "NAME\n"
	@printf "  tirosh-vitalserver-docs - documentation site targets\n"
	@printf "\n"
	@printf "SYNOPSIS\n"
	@printf "  make docs/{serve|build} [DOCS_PORT=8000] [DOCS_PORT_MAX=8100]\n"
	@printf "\n"
	@printf "DOCS TARGETS\n"
	@printf "  docs/serve                    Serve MkDocs site, choosing the first free port\n"
	@printf "  docs/build                    Build MkDocs site into site/\n"
	@printf "\n"
	@printf "VARIABLES\n"
	@printf "  DOCS_HOST=%s\n" "$(DOCS_HOST)"
	@printf "  DOCS_PORT=%s\n" "$(DOCS_PORT)"
	@printf "  DOCS_PORT_MAX=%s\n" "$(DOCS_PORT_MAX)"

help/all:
	@$(MAKE) --no-print-directory help/compose
	@printf "\n"
	@$(MAKE) --no-print-directory help/runtime
	@printf "\n"
	@$(MAKE) --no-print-directory help/dist
	@printf "\n"
	@$(MAKE) --no-print-directory help/pwa
	@printf "\n"
	@$(MAKE) --no-print-directory help/docs
	@printf "\n"
	@$(MAKE) --no-print-directory help/dev
	@printf "\n"
	@$(MAKE) --no-print-directory help/devtools
	@printf "\n"
	@$(MAKE) --no-print-directory help/proxy
