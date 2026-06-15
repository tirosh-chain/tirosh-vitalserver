ENV_ARGS = \
	$(PROXY_ARGS) \
	--python "$(PYTHON)" \
	--uv "$(UV)" \
	--compose "$(COMPOSE)"

.PHONY: dev/bootstrap dev/doctor testkit/install-release require-uv

dev/bootstrap: repo/init
	$(DEVTOOLS_RUNNER) env-bootstrap $(ENV_ARGS)

dev/doctor:
	$(DEVTOOLS_RUNNER) env-doctor $(ENV_ARGS)

testkit/install-release:
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
