.PHONY: testkit-health testkit-smoke testkit-verify testkit-load testkit-stream
.PHONY: require-testkit-runtime

require-testkit-runtime:
	@$(TESTKIT_RUNNER) --help >/dev/null

testkit-health: require-testkit-runtime
	$(TESTKIT) health

testkit-verify: require-testkit-runtime up
	$(TESTKIT) verify

testkit-smoke: require-testkit-runtime up
	$(TESTKIT) smoke

testkit-load: require-testkit-runtime up
	$(TESTKIT) load

testkit-stream: require-testkit-runtime up
	@status=0; \
	$(TESTKIT) stream || status=$$?; \
	if [ "$$status" = "130" ]; then \
		printf "testkit stream interrupted\n"; \
	else \
		exit "$$status"; \
	fi
