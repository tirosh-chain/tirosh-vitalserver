.PHONY: internal/vm/installed/status internal/vm/installed/health internal/vm/installed/smoke

internal/vm/installed/status:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-installed-status

internal/vm/installed/health:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-installed-health \
		--proxy-port "$(VITALSERVER_PROXY_PORT)"

internal/vm/installed/smoke:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-installed-smoke \
		--proxy-port "$(VITALSERVER_PROXY_PORT)"
