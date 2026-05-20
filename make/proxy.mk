PROXY_RUNTIME_DIR ?= .tmp/macos-nginx
PROXY_CONFIG ?= $(PROXY_RUNTIME_DIR)/vitalserver.conf
VITALSERVER_PROXY_PORT ?= 80
VITALSERVER_BIND_HOST ?= 127.0.0.1
VITALSERVER_HTTP_PORT ?= 18080
VITALSERVER_TRUST_PROXY ?= 1
NGINX_BIN ?= $(shell command -v nginx 2>/dev/null || printf "/opt/homebrew/bin/nginx")
ifeq ($(VITALSERVER_PROXY_PORT),80)
NGINX_CMD ?= sudo $(NGINX_BIN)
else
NGINX_CMD ?= $(NGINX_BIN)
endif
NGINX_CONF ?= /Library/Application Support/TiroshVitalServer/nginx/vitalserver.conf
NGINX_PREFIX ?= /Library/Application Support/TiroshVitalServer/nginx

.PHONY: proxy-config proxy-write-config proxy-test proxy-start proxy-run proxy-stop proxy-clean proxy-reload proxy-status proxy-plist

proxy-config:
	@VITALSERVER_PROXY_PORT="$(VITALSERVER_PROXY_PORT)" \
	VITALSERVER_HTTP_PORT="$(VITALSERVER_HTTP_PORT)" \
	"$(PYTHON)" -c 'import os, pathlib; p=pathlib.Path("infra/macos-nginx/vitalserver.conf.template"); s=p.read_text(); print(s.replace("$${VITALSERVER_PROXY_PORT}", os.environ["VITALSERVER_PROXY_PORT"]).replace("$${VITALSERVER_HTTP_PORT}", os.environ["VITALSERVER_HTTP_PORT"]), end="")'

proxy-write-config:
	@mkdir -p "$(PROXY_RUNTIME_DIR)/logs"
	@VITALSERVER_PROXY_PORT="$(VITALSERVER_PROXY_PORT)" \
	VITALSERVER_HTTP_PORT="$(VITALSERVER_HTTP_PORT)" \
	PROXY_CONFIG="$(PROXY_CONFIG)" \
	"$(PYTHON)" -c 'import os, pathlib; p=pathlib.Path("infra/macos-nginx/vitalserver.conf.template"); s=p.read_text(); pathlib.Path(os.environ["PROXY_CONFIG"]).write_text(s.replace("$${VITALSERVER_PROXY_PORT}", os.environ["VITALSERVER_PROXY_PORT"]).replace("$${VITALSERVER_HTTP_PORT}", os.environ["VITALSERVER_HTTP_PORT"]))'
	@printf "Wrote %s\n" "$(PROXY_CONFIG)"

proxy-test: proxy-write-config
	$(NGINX_CMD) -t -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)"

proxy-start: proxy-test proxy-run

proxy-run:
	@if [ -f "$(PROXY_RUNTIME_DIR)/logs/nginx.pid" ]; then \
		pid="$$(cat "$(PROXY_RUNTIME_DIR)/logs/nginx.pid")"; \
	else \
		pid=""; \
	fi; \
	if [ -n "$$pid" ] && kill -0 "$$pid" >/dev/null 2>&1; then \
		$(NGINX_CMD) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)" -s reload; \
		printf "Proxy reloaded: http://localhost:%s -> http://127.0.0.1:%s\n" "$(VITALSERVER_PROXY_PORT)" "$(VITALSERVER_HTTP_PORT)"; \
	else \
		$(NGINX_CMD) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)"; \
		printf "Proxy: http://localhost:%s -> http://127.0.0.1:%s\n" "$(VITALSERVER_PROXY_PORT)" "$(VITALSERVER_HTTP_PORT)"; \
	fi

proxy-stop:
	@pid_file="$(PROXY_RUNTIME_DIR)/logs/nginx.pid"; \
	nginx_args='-p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)"'; \
	if [ -f "$$pid_file" ]; then \
		pid="$$(cat "$$pid_file")"; \
	else \
		pid=""; \
	fi; \
	if [ -n "$$pid" ] && kill -0 "$$pid" >/dev/null 2>&1; then \
		$(NGINX_CMD) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)" -s quit; \
		printf "nginx proxy stop requested: pid %s\n" "$$pid"; \
	elif [ -f "$(PROXY_CONFIG)" ]; then \
		if [ -n "$$pid" ]; then \
			printf "nginx proxy pid file is stale: %s\n" "$$pid"; \
		else \
			printf "nginx proxy pid file is missing; trying config-based stop\n"; \
		fi; \
		if $(NGINX_CMD) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)" -s quit >/tmp/tirosh-vitalserver-nginx-stop.log 2>&1; then \
			printf "nginx proxy stop requested with %s\n" "$$nginx_args"; \
		else \
			if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$(VITALSERVER_PROXY_PORT)" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $$1}' | grep -qx nginx; then \
				cat /tmp/tirosh-vitalserver-nginx-stop.log; \
				printf "warn: nginx is still listening on port %s; try running this in an interactive terminal:\n" "$(VITALSERVER_PROXY_PORT)"; \
				printf "  %s -p %s -c %s -s quit\n" "$(NGINX_CMD)" "$(CURDIR)/$(PROXY_RUNTIME_DIR)" "$(CURDIR)/$(PROXY_CONFIG)"; \
				exit 1; \
			else \
				printf "nginx proxy is already stopped\n"; \
			fi; \
		fi; \
	else \
		printf "nginx proxy is already stopped: missing %s and %s\n" "$$pid_file" "$(PROXY_CONFIG)"; \
	fi

proxy-clean: proxy-stop
	rm -rf "$(PROXY_RUNTIME_DIR)"

proxy-reload: proxy-test
	$(NGINX_CMD) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)" -s reload

proxy-status:
	@backend_url="http://$(VITALSERVER_BIND_HOST):$(VITALSERVER_HTTP_PORT)/check"; \
	if [ -f "$(PROXY_RUNTIME_DIR)/logs/nginx.pid" ]; then \
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
	fi; \
	if command -v pgrep >/dev/null 2>&1; then \
		matches="$$(pgrep -f "$(CURDIR)/$(PROXY_CONFIG)" 2>/dev/null | paste -sd, -)"; \
		if [ -n "$$matches" ]; then \
			printf "nginx proxy process matches config: %s\n" "$$matches"; \
		fi; \
	fi; \
	if command -v lsof >/dev/null 2>&1; then \
		listeners="$$(lsof -nP -iTCP:"$(VITALSERVER_PROXY_PORT)" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $$1 "/" $$2}' | sort -u | paste -sd, -)"; \
		if [ -n "$$listeners" ]; then \
			printf "proxy port %s listeners: %s\n" "$(VITALSERVER_PROXY_PORT)" "$$listeners"; \
		else \
			printf "proxy port %s has no listener\n" "$(VITALSERVER_PROXY_PORT)"; \
		fi; \
	else \
		printf "optional missing: lsof; skipping proxy port listener check\n"; \
	fi; \
	if command -v curl >/dev/null 2>&1; then \
		if curl -fsS --max-time 2 "$$backend_url" >/dev/null 2>&1; then \
			printf "backend is reachable: %s\n" "$$backend_url"; \
		else \
			printf "backend is not reachable: %s\n" "$$backend_url"; \
			printf "hint: run 'docker compose ps' and check that app publishes %s:%s\n" "$(VITALSERVER_BIND_HOST)" "$(VITALSERVER_HTTP_PORT)"; \
		fi; \
	else \
		printf "optional missing: curl; skipping backend health check\n"; \
	fi

proxy-plist:
	@NGINX_BIN="$(NGINX_BIN)" \
	NGINX_CONF="$(NGINX_CONF)" \
	NGINX_PREFIX="$(NGINX_PREFIX)" \
	"$(PYTHON)" -c 'import os, pathlib; p=pathlib.Path("infra/macos-nginx/com.tirosh.vitalserver-proxy.plist.template"); s=p.read_text(); print(s.replace("$${NGINX_BIN}", os.environ["NGINX_BIN"]).replace("$${NGINX_CONF}", os.environ["NGINX_CONF"]).replace("$${NGINX_PREFIX}", os.environ["NGINX_PREFIX"]), end="")'
