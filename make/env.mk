ENV_ARGS = \
	$(PROXY_ARGS) \
	--python "$(PYTHON)" \
	--uv "$(UV)" \
	--compose "$(COMPOSE)"

.PHONY: bootstrap doctor install-testkit-release require-uv

bootstrap: init
	$(DEVTOOLS_RUNNER) env-bootstrap $(ENV_ARGS)

doctor:
	$(DEVTOOLS_RUNNER) env-doctor $(ENV_ARGS)

install-testkit-release:
	$(PYTHON) scripts/install_testkit_release.py \
		--testkit-version "$(TESTKIT_VERSION)" \
		--testkit-release-tag "$(TESTKIT_RELEASE_TAG)" \
		--testkit-release-dir "$(TESTKIT_RELEASE_DIR)" \
		--python "$(PYTHON)"

require-uv:
	@command -v "$(UV)" >/dev/null 2>&1 || { \
		printf "missing: uv\n"; \
		printf "Install uv to run Python developer checks.\n"; \
		printf "See https://docs.astral.sh/uv/getting-started/installation/\n"; \
		exit 127; \
	}
