.PHONY: testkit/health testkit/smoke testkit/verify testkit/load testkit/stream testkit/recorder-ingress/replay
.PHONY: require-testkit-runtime

require-testkit-runtime:
	@$(TESTKIT_RUNNER) --help >/dev/null

testkit/health: require-testkit-runtime
	$(TESTKIT) health

testkit/verify: require-testkit-runtime compose/up
	$(TESTKIT) verify

testkit/smoke: require-testkit-runtime compose/up
	$(TESTKIT) smoke

testkit/load: require-testkit-runtime compose/up
	$(TESTKIT) load

testkit/stream: require-testkit-runtime compose/up
	@status=0; \
	$(TESTKIT) stream || status=$$?; \
	if [ "$$status" = "130" ]; then \
		printf "testkit stream interrupted\n"; \
	else \
		exit "$$status"; \
	fi

testkit/recorder-ingress/replay: require-testkit-runtime
	RECORDER_INGRESS_SEND_DATA_MODE=spool_and_replay \
	RECORDER_INGRESS_SEND_DATA_REPLAY_ENABLED=1 \
	RECORDER_INGRESS_SEND_DATA_REPLAY_INTERVAL_MS=250 \
	RECORDER_INGRESS_SEND_DATA_REPLAY_RATE_LIMIT_PER_SECOND=20 \
	$(PYTHON) scripts/recorder_ingress_compose_e2e.py \
		--compose "$(DOCKER_COMPOSE)" \
		--bind-host "$(VITALSERVER_BIND_HOST)" \
		--http-port "$(VITALSERVER_HTTP_PORT)"
