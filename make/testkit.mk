.PHONY: testkit-health testkit-smoke testkit-verify testkit-load testkit-stream

testkit-health:
	$(TESTKIT) health

testkit-smoke: up
	$(TESTKIT) smoke

testkit-verify: up
	$(TESTKIT) verify

testkit-load: up
	$(TESTKIT) load

testkit-stream: up
	$(TESTKIT) stream || code=$$?; \
	if [ "$$code" -eq 130 ]; then \
		echo "testkit stream interrupted"; \
		exit 0; \
	fi; \
	exit "$$code"
