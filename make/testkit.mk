.PHONY: testkit-health testkit-smoke testkit-verify testkit-load testkit-stream

testkit-health: require-uv
	$(TESTKIT) health

testkit-smoke: require-uv up
	$(TESTKIT) smoke

testkit-verify: require-uv up
	$(TESTKIT) verify

testkit-load: require-uv up
	$(TESTKIT) load

testkit-stream: require-uv up
	$(TESTKIT) stream || code=$$?; \
	if [ "$$code" -eq 130 ]; then \
		echo "testkit stream interrupted"; \
		exit 0; \
	fi; \
	exit "$$code"
