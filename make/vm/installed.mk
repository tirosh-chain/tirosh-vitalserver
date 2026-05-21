.PHONY: vm-installed-status vm-installed-health

vm-installed-status:
	@printf "Installed VM runtime\n"
	@test -x "$(VM_INSTALL_BIN)" && printf "  launcher: %s\n" "$(VM_INSTALL_BIN)" || printf "  missing launcher: %s\n" "$(VM_INSTALL_BIN)"
	@test -x "$(VM_INSTALL_PROXY_RUN)" && printf "  proxy runner: %s\n" "$(VM_INSTALL_PROXY_RUN)" || printf "  missing proxy runner: %s\n" "$(VM_INSTALL_PROXY_RUN)"
	@test -x "$(VM_INSTALL_UNINSTALL)" && printf "  uninstaller: %s\n" "$(VM_INSTALL_UNINSTALL)" || printf "  missing uninstaller: %s\n" "$(VM_INSTALL_UNINSTALL)"
	@test -x "$(VM_INSTALL_NGINX_BIN)" && printf "  nginx: %s\n" "$(VM_INSTALL_NGINX_BIN)" || printf "  missing nginx: %s\n" "$(VM_INSTALL_NGINX_BIN)"
	@launchctl print system/com.tirosh.vitalserver-vm >/dev/null 2>&1 && printf "  launchd vm: loaded\n" || printf "  launchd vm: not loaded\n"
	@launchctl print system/com.tirosh.vitalserver-proxy >/dev/null 2>&1 && printf "  launchd proxy: loaded\n" || printf "  launchd proxy: not loaded\n"
	@launchctl print system/com.tirosh.vitalserver-watchdog >/dev/null 2>&1 && printf "  launchd watchdog: loaded\n" || printf "  launchd watchdog: not loaded\n"
	@if [ -s "$(VM_INSTALLED_IP_FILE)" ]; then \
		printf "  vm ip: %s\n" "$$(cat "$(VM_INSTALLED_IP_FILE)")"; \
	else \
		printf "  vm ip: waiting for %s\n" "$(VM_INSTALLED_IP_FILE)"; \
	fi

vm-installed-health: vm-installed-status
	@status=0; \
	if [ -s "$(VM_INSTALLED_IP_FILE)" ]; then \
		vm_ip="$$(cat "$(VM_INSTALLED_IP_FILE)")"; \
		code="$$(curl -sS -I -o /dev/null -w '%{http_code}' --max-time 5 "http://$$vm_ip/" 2>/dev/null)" && http_status=0 || http_status=$$?; \
		if [ "$$http_status" -eq 0 ] && [ "$$code" -ge 200 ] && [ "$$code" -lt 400 ]; then \
			printf "  guest http: ok http://%s/ -> %s\n" "$$vm_ip" "$$code"; \
		else \
			printf "  guest http: failed http://%s/ -> %s\n" "$$vm_ip" "$${code:-curl-error}" >&2; \
			status=1; \
		fi; \
	else \
		status=1; \
	fi; \
	code="$$(curl -sS -I -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$(VITALSERVER_PROXY_PORT)/" 2>/dev/null)" && http_status=0 || http_status=$$?; \
	if [ "$$http_status" -eq 0 ] && [ "$$code" -ge 200 ] && [ "$$code" -lt 400 ]; then \
		printf "  host proxy: ok http://127.0.0.1:%s/ -> %s\n" "$(VITALSERVER_PROXY_PORT)" "$$code"; \
	else \
		printf "  host proxy: failed http://127.0.0.1:%s/ -> %s\n" "$(VITALSERVER_PROXY_PORT)" "$${code:-curl-error}" >&2; \
		status=1; \
	fi; \
	exit $$status
