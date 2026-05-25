PROXY_RUNTIME_DIR ?= .tmp/macos-nginx
PROXY_CONFIG ?= $(PROXY_RUNTIME_DIR)/vitalserver.conf
VITALSERVER_PROXY_PORT ?= 80
VITALSERVER_BIND_HOST ?= 127.0.0.1
VITALSERVER_HTTP_PORT ?= 18080
PROXY_UPSTREAM ?= 127.0.0.1:$(VITALSERVER_HTTP_PORT)
VITALSERVER_TRUST_PROXY ?= 1
NGINX_BIN ?= $(shell command -v nginx 2>/dev/null || printf "/opt/homebrew/bin/nginx")
NGINX_CONF ?= /Library/Application Support/TiroshVitalServer/nginx/vitalserver.conf
NGINX_PREFIX ?= /Library/Application Support/TiroshVitalServer/nginx

PROXY_ARGS = \
	--runtime-dir "$(PROXY_RUNTIME_DIR)" \
	--config "$(PROXY_CONFIG)" \
	--port "$(VITALSERVER_PROXY_PORT)" \
	--bind-host "$(VITALSERVER_BIND_HOST)" \
	--http-port "$(VITALSERVER_HTTP_PORT)" \
	--upstream "$(PROXY_UPSTREAM)" \
	--trust-proxy "$(VITALSERVER_TRUST_PROXY)" \
	--nginx-bin "$(NGINX_BIN)" \
	--nginx-conf "$(NGINX_CONF)" \
	--nginx-prefix "$(NGINX_PREFIX)"

.PHONY: proxy-config proxy-write-config proxy-test proxy-start proxy-run proxy-port-check proxy-stop proxy-stop-orphans proxy-clean proxy-reload proxy-status proxy-plist

proxy-config:
	$(DEVTOOLS_RUNNER) proxy-config $(PROXY_ARGS)

proxy-write-config:
	$(DEVTOOLS_RUNNER) proxy-write-config $(PROXY_ARGS)

proxy-test:
	$(DEVTOOLS_RUNNER) proxy-test $(PROXY_ARGS)

proxy-start:
	$(DEVTOOLS_RUNNER) proxy-start $(PROXY_ARGS)

proxy-run: proxy-start

proxy-port-check:
	$(DEVTOOLS_RUNNER) proxy-port-check $(PROXY_ARGS)

proxy-stop:
	$(DEVTOOLS_RUNNER) proxy-stop $(PROXY_ARGS)

proxy-stop-orphans:
	$(DEVTOOLS_RUNNER) proxy-stop-orphans $(PROXY_ARGS)

proxy-clean:
	$(DEVTOOLS_RUNNER) proxy-clean $(PROXY_ARGS)

proxy-reload:
	$(DEVTOOLS_RUNNER) proxy-reload $(PROXY_ARGS)

proxy-status:
	$(DEVTOOLS_RUNNER) proxy-status $(PROXY_ARGS)

proxy-plist:
	$(DEVTOOLS_RUNNER) proxy-plist $(PROXY_ARGS)
