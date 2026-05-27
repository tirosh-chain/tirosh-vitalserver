.PHONY: vm-installed-status vm-installed-health

vm-installed-status:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-installed-status

vm-installed-health:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-installed-health \
		--proxy-port "$(VITALSERVER_PROXY_PORT)"
