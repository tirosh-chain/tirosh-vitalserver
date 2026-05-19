PROXY_RUNTIME_DIR ?= .tmp/macos-nginx
PROXY_CONFIG ?= $(PROXY_RUNTIME_DIR)/vitalserver.conf
VITALSERVER_PROXY_PORT ?= 8080
VITALSERVER_HTTP_PORT ?= 18080
NGINX ?= nginx
NGINX_BIN ?= /opt/homebrew/bin/nginx
NGINX_CONF ?= /Library/Application Support/TiroshVitalServer/nginx/vitalserver.conf
NGINX_PREFIX ?= /Library/Application Support/TiroshVitalServer/nginx

.PHONY: proxy-config proxy-write-config proxy-test proxy-start proxy-stop proxy-reload proxy-status proxy-plist

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
	$(NGINX) -t -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)"

proxy-start: proxy-test
	$(NGINX) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)"
	@printf "Proxy: http://localhost:%s -> http://127.0.0.1:%s\n" "$(VITALSERVER_PROXY_PORT)" "$(VITALSERVER_HTTP_PORT)"

proxy-stop:
	$(NGINX) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)" -s quit

proxy-reload: proxy-test
	$(NGINX) -p "$(CURDIR)/$(PROXY_RUNTIME_DIR)" -c "$(CURDIR)/$(PROXY_CONFIG)" -s reload

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
