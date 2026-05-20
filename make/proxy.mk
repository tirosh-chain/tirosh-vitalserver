PROXY_RUNTIME_DIR ?= .tmp/macos-nginx
PROXY_CONFIG ?= $(PROXY_RUNTIME_DIR)/vitalserver.conf
VITALSERVER_PROXY_PORT ?= 80
VITALSERVER_BIND_HOST ?= 127.0.0.1
VITALSERVER_HTTP_PORT ?= 18080
PROXY_UPSTREAM ?= 127.0.0.1:$(VITALSERVER_HTTP_PORT)
VITALSERVER_TRUST_PROXY ?= 1
NGINX_BIN ?= $(shell command -v nginx 2>/dev/null || printf "/opt/homebrew/bin/nginx")
ifeq ($(VITALSERVER_PROXY_PORT),80)
NGINX_CMD ?= sudo $(NGINX_BIN)
else
NGINX_CMD ?= $(NGINX_BIN)
endif
NGINX_CONF ?= /Library/Application Support/TiroshVitalServer/nginx/vitalserver.conf
NGINX_PREFIX ?= /Library/Application Support/TiroshVitalServer/nginx

.PHONY: proxy-config proxy-write-config proxy-test proxy-start proxy-run proxy-port-check proxy-stop proxy-clean proxy-reload proxy-status proxy-plist

proxy-config:
	@VITALSERVER_PROXY_PORT="$(VITALSERVER_PROXY_PORT)" \
	PROXY_UPSTREAM="$(PROXY_UPSTREAM)" \
	"$(PYTHON)" -c 'import os, pathlib; p=pathlib.Path("infra/macos-nginx/vitalserver.conf.template"); s=p.read_text(); print(s.replace("$${VITALSERVER_PROXY_PORT}", os.environ["VITALSERVER_PROXY_PORT"]).replace("$${PROXY_UPSTREAM}", os.environ["PROXY_UPSTREAM"]), end="")'

proxy-write-config:
	@mkdir -p "$(PROXY_RUNTIME_DIR)/logs"
	@VITALSERVER_PROXY_PORT="$(VITALSERVER_PROXY_PORT)" \
	PROXY_UPSTREAM="$(PROXY_UPSTREAM)" \
	PROXY_CONFIG="$(PROXY_CONFIG)" \
	"$(PYTHON)" -c 'import os, pathlib; p=pathlib.Path("infra/macos-nginx/vitalserver.conf.template"); s=p.read_text(); pathlib.Path(os.environ["PROXY_CONFIG"]).write_text(s.replace("$${VITALSERVER_PROXY_PORT}", os.environ["VITALSERVER_PROXY_PORT"]).replace("$${PROXY_UPSTREAM}", os.environ["PROXY_UPSTREAM"]))'
	@printf "Wrote %s\n" "$(PROXY_CONFIG)"

proxy-test: proxy-write-config
	$(NGINX_CMD) -t -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)"

proxy-start: proxy-test proxy-run

proxy-port-check:
	@if command -v lsof >/dev/null 2>&1; then \
		if [ -f "$(PROXY_RUNTIME_DIR)/logs/nginx.pid" ]; then \
			own_pid="$$(cat "$(PROXY_RUNTIME_DIR)/logs/nginx.pid" 2>/dev/null || true)"; \
		else \
			own_pid=""; \
		fi; \
		listeners="$$(lsof -nP -iTCP:"$(VITALSERVER_PROXY_PORT)" -sTCP:LISTEN 2>/dev/null | awk -v own="$$own_pid" 'NR>1 && $$2 != own {print $$1 "/" $$2}' | sort -u | paste -sd, -)"; \
		if [ -n "$$listeners" ]; then \
			printf "error: proxy port %s is already in use by %s\n" "$(VITALSERVER_PROXY_PORT)" "$$listeners" >&2; \
			printf "Stop that process or use VITALSERVER_PROXY_PORT=<port>.\n" >&2; \
			exit 1; \
		fi; \
	fi

proxy-run:
	@if [ -f "$(PROXY_RUNTIME_DIR)/logs/nginx.pid" ]; then \
		pid="$$(cat "$(PROXY_RUNTIME_DIR)/logs/nginx.pid")"; \
	else \
		pid=""; \
	fi; \
	if [ -n "$$pid" ] && kill -0 "$$pid" >/dev/null 2>&1; then \
		$(NGINX_CMD) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)" -s reload || exit $$?; \
		printf "Proxy reloaded: http://localhost:%s -> http://%s\n" "$(VITALSERVER_PROXY_PORT)" "$(PROXY_UPSTREAM)"; \
	else \
		$(MAKE) proxy-port-check || exit $$?; \
		$(NGINX_CMD) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)" || exit $$?; \
		printf "Proxy: http://localhost:%s -> http://%s\n" "$(VITALSERVER_PROXY_PORT)" "$(PROXY_UPSTREAM)"; \
	fi

proxy-stop:
	@if [ -f "$(PROXY_RUNTIME_DIR)/logs/nginx.pid" ]; then \
		pid="$$(cat "$(PROXY_RUNTIME_DIR)/logs/nginx.pid")"; \
		if [ -n "$$pid" ] && kill -0 "$$pid" >/dev/null 2>&1; then \
			$(NGINX_CMD) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)" -s quit; \
		else \
			printf "nginx proxy is already stopped\n"; \
		fi; \
	else \
		printf "nginx proxy is already stopped\n"; \
	fi

proxy-clean: proxy-stop
	rm -rf "$(PROXY_RUNTIME_DIR)"

proxy-reload: proxy-test
	$(NGINX_CMD) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)" -s reload

proxy-status:
	@if [ -f "$(PROXY_RUNTIME_DIR)/logs/nginx.pid" ]; then \
		pid="$$(cat "$(PROXY_RUNTIME_DIR)/logs/nginx.pid")"; \
		if [ -z "$$pid" ]; then \
			printf "nginx proxy is not running: empty pid file %s/logs/nginx.pid\n" "$(PROXY_RUNTIME_DIR)"; \
		elif kill -0 "$$pid" >/dev/null 2>&1; then \
			printf "nginx proxy is running: pid %s\n" "$$pid"; \
		else \
			printf "nginx proxy pid file exists, but process is not running: %s\n" "$$pid"; \
		fi; \
	else \
		printf "nginx proxy is not running: missing %s/logs/nginx.pid\n" "$(PROXY_RUNTIME_DIR)"; \
	fi

proxy-plist:
	@NGINX_BIN="$(NGINX_BIN)" \
	NGINX_CONF="$(NGINX_CONF)" \
	NGINX_PREFIX="$(NGINX_PREFIX)" \
	"$(PYTHON)" -c 'import os, pathlib; p=pathlib.Path("infra/macos-nginx/com.tirosh.vitalserver-proxy.plist.template"); s=p.read_text(); print(s.replace("$${NGINX_BIN}", os.environ["NGINX_BIN"]).replace("$${NGINX_CONF}", os.environ["NGINX_CONF"]).replace("$${NGINX_PREFIX}", os.environ["NGINX_PREFIX"]), end="")'
