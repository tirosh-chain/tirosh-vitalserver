.PHONY: testkit-health testkit-smoke testkit-verify testkit-load testkit-stream

testkit-health: require-testkit-runtime
	$(TESTKIT) health

testkit-smoke: require-testkit-runtime up
	$(TESTKIT) smoke

testkit-verify: require-testkit-runtime up
	$(TESTKIT) verify

testkit-load: require-testkit-runtime up
	$(TESTKIT) load

testkit-stream: require-testkit-runtime up
	$(TESTKIT) stream || code=$$?; \
	if [ "$$code" -eq 130 ]; then \
		echo "testkit stream interrupted"; \
		exit 0; \
	fi; \
	exit "$$code"
