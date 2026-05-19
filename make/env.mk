.PHONY: bootstrap doctor install-testkit-release require-testkit-runtime require-uv

bootstrap: init
	@printf "Preparing local workspace\n"
	@if [ -f .env ]; then \
		printf "ok: .env exists\n"; \
	else \
		cp .env.example .env; \
		printf "created: .env from .env.example\n"; \
	fi
	@mkdir -p "$(PROXY_RUNTIME_DIR)/logs"
	@$(MAKE) proxy-write-config
	@if command -v "$(UV)" >/dev/null 2>&1; then \
		printf "Syncing Python workspace with %s\n" "$(UV)"; \
		if "$(UV)" sync; then \
			printf "ok: Python workspace synced\n"; \
		else \
			printf "warn: Python workspace sync failed; continuing because testkit/dev env is optional for make up\n"; \
		fi; \
	else \
		printf "uv not found; skipping Python workspace sync.\n"; \
		printf "Install uv only when you need testkit, lint, typecheck, or pytest.\n"; \
	fi
	@$(MAKE) doctor

doctor:
	@printf "Checking local environment\n"
	@command -v git >/dev/null 2>&1 || { printf "missing: git\n"; exit 1; }
	@printf "ok: git\n"
	@command -v "$(PYTHON)" >/dev/null 2>&1 || { printf "missing: $(PYTHON)\n"; exit 1; }
	@printf "ok: $(PYTHON)\n"
	@command -v docker >/dev/null 2>&1 || { printf "missing: docker\n"; exit 1; }
	@printf "ok: docker\n"
	@docker info >/dev/null 2>&1 || { printf "error: Docker daemon is not reachable\n"; exit 1; }
	@printf "ok: Docker daemon\n"
	@docker compose version >/dev/null 2>&1 || { printf "missing: Docker Compose v2\n"; exit 1; }
	@printf "ok: Docker Compose v2\n"
	@if [ -e vendor/vitalserver/.git ]; then \
		printf "ok: vendor/vitalserver submodule\n"; \
	else \
		printf "missing: vendor/vitalserver submodule; run 'make init'\n"; \
		exit 1; \
	fi
	@if [ -x "$(NGINX_BIN)" ] || command -v "$(NGINX_BIN)" >/dev/null 2>&1; then \
		printf "ok: nginx (%s)\n" "$(NGINX_BIN)"; \
	else \
		printf "missing: nginx; install with 'brew install nginx' or set NGINX_BIN=/path/to/nginx\n"; \
		exit 1; \
	fi
	@mkdir -p "$(PROXY_RUNTIME_DIR)/logs"
	@VITALSERVER_PROXY_PORT="$(VITALSERVER_PROXY_PORT)" \
	VITALSERVER_HTTP_PORT="$(VITALSERVER_HTTP_PORT)" \
	PROXY_CONFIG="$(PROXY_CONFIG)" \
	"$(PYTHON)" -c 'import os, pathlib; p=pathlib.Path("infra/macos-nginx/vitalserver.conf.template"); s=p.read_text(); pathlib.Path(os.environ["PROXY_CONFIG"]).write_text(s.replace("$${VITALSERVER_PROXY_PORT}", os.environ["VITALSERVER_PROXY_PORT"]).replace("$${VITALSERVER_HTTP_PORT}", os.environ["VITALSERVER_HTTP_PORT"]))'
	@"$(NGINX_BIN)" -t -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)" >"$(PROXY_RUNTIME_DIR)/logs/nginx-test.log" 2>&1 || { \
		cat "$(PROXY_RUNTIME_DIR)/logs/nginx-test.log"; \
		printf "error: nginx proxy config is invalid\n"; \
		exit 1; \
	}
	@printf "ok: nginx proxy config\n"
	@if [ "$(VITALSERVER_PROXY_PORT)" -lt 1024 ] 2>/dev/null && [ "$$(id -u)" != "0" ]; then \
		if command -v sudo >/dev/null 2>&1; then \
			if sudo -n true >/dev/null 2>&1; then \
				printf "ok: sudo is available for privileged proxy port %s\n" "$(VITALSERVER_PROXY_PORT)"; \
			else \
				printf "warn: proxy port %s requires sudo; 'make up' may ask for a password\n" "$(VITALSERVER_PROXY_PORT)"; \
			fi; \
		else \
			printf "error: proxy port %s requires root, but sudo is missing\n" "$(VITALSERVER_PROXY_PORT)"; \
			exit 1; \
		fi; \
	fi
	@if command -v lsof >/dev/null 2>&1; then \
		listeners=$$(lsof -nP -iTCP:"$(VITALSERVER_PROXY_PORT)" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $$1 "/" $$2}' | sort -u | paste -sd, -); \
		if [ -n "$$listeners" ]; then \
			case "$$listeners" in \
				*nginx*) printf "ok: proxy port %s is already used by nginx (%s)\n" "$(VITALSERVER_PROXY_PORT)" "$$listeners" ;; \
				*) printf "warn: proxy port %s is already in use by %s\n" "$(VITALSERVER_PROXY_PORT)" "$$listeners" ;; \
			esac; \
		else \
			printf "ok: proxy port %s is available\n" "$(VITALSERVER_PROXY_PORT)"; \
		fi; \
	else \
		printf "optional missing: lsof; skipping proxy port check\n"; \
	fi
	@VITALSERVER_BIND_HOST="$(VITALSERVER_BIND_HOST)" \
	VITALSERVER_HTTP_PORT="$(VITALSERVER_HTTP_PORT)" \
	VITALSERVER_TRUST_PROXY="$(VITALSERVER_TRUST_PROXY)" \
	$(COMPOSE) config >/dev/null || { printf "error: docker compose config is invalid\n"; exit 1; }
	@printf "ok: compose config (%s:%s, trust_proxy=%s)\n" "$(VITALSERVER_BIND_HOST)" "$(VITALSERVER_HTTP_PORT)" "$(VITALSERVER_TRUST_PROXY)"
	@if [ "$(VITALSERVER_BIND_HOST)" = "127.0.0.1" ]; then \
		printf "ok: Docker backend is loopback-only\n"; \
	else \
		printf "warn: VITALSERVER_BIND_HOST=%s exposes Docker backend directly\n" "$(VITALSERVER_BIND_HOST)"; \
	fi
	@if command -v "$(UV)" >/dev/null 2>&1; then \
		printf "ok: uv\n"; \
	else \
		printf "optional missing: uv; checking installed testkit package\n"; \
		"$(PYTHON)" -c "import pydantic_settings, tirosh_vitalserver.testkit" >/dev/null 2>&1 \
			&& printf "ok: installed testkit runtime\n" \
			|| printf "optional missing: installed testkit runtime; run 'make install-testkit-release'\n"; \
	fi

install-testkit-release:
	@command -v gh >/dev/null 2>&1 || { \
		printf "missing: gh\n"; \
		printf "Install GitHub CLI and run 'gh auth login', or download the wheel from GitHub Release manually.\n"; \
		exit 127; \
	}
	@command -v "$(PYTHON)" >/dev/null 2>&1 || { printf "missing: $(PYTHON)\n"; exit 127; }
	@mkdir -p "$(TESTKIT_RELEASE_DIR)"
	@gh release download "$(TESTKIT_RELEASE_TAG)" \
		--repo tirosh-chain/tirosh-vitalserver \
		--pattern "*.whl" \
		--dir "$(TESTKIT_RELEASE_DIR)" \
		--clobber
	@wheel=$$(ls "$(TESTKIT_RELEASE_DIR)"/tirosh_vitalserver_testkit-$(TESTKIT_VERSION)-*.whl | head -n 1); \
		printf "Installing %s with %s\n" "$$wheel" "$(PYTHON)"; \
		"$(PYTHON)" -m pip install --upgrade "$$wheel" pydantic-settings

require-testkit-runtime:
	@if command -v "$(UV)" >/dev/null 2>&1; then \
		exit 0; \
	fi
	@command -v "$(PYTHON)" >/dev/null 2>&1 || { printf "missing: $(PYTHON)\n"; exit 127; }
	@"$(PYTHON)" -c "import pydantic_settings, tirosh_vitalserver.testkit" >/dev/null 2>&1 || { \
		printf "missing: installed testkit runtime\n"; \
		printf "Run 'make install-testkit-release' or install uv for workspace execution.\n"; \
		exit 127; \
	}

require-uv:
	@command -v "$(UV)" >/dev/null 2>&1 || { \
		printf "missing: uv\n"; \
		printf "Install uv to run Python testkit and developer checks.\n"; \
		printf "See https://docs.astral.sh/uv/getting-started/installation/\n"; \
		exit 127; \
	}
