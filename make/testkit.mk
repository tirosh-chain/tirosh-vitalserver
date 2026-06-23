.PHONY: testkit/health testkit/smoke testkit/verify testkit/load testkit/stream testkit/recorder-ingress/replay testkit/recorder-ingress/load testkit/recorder-ingress/backpressure
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
		--http-port "$(VITALSERVER_HTTP_PORT)" \
		--replay-batch-size 5

testkit/recorder-ingress/load: require-testkit-runtime
	RECORDER_INGRESS_SEND_DATA_MODE=spool_and_replay \
	RECORDER_INGRESS_SEND_DATA_REPLAY_ENABLED=1 \
	RECORDER_INGRESS_SEND_DATA_REPLAY_INTERVAL_MS=250 \
	RECORDER_INGRESS_SEND_DATA_REPLAY_RATE_LIMIT_PER_SECOND=50 \
	$(PYTHON) scripts/recorder_ingress_compose_e2e.py \
		--compose "$(DOCKER_COMPOSE)" \
		--bind-host "$(VITALSERVER_BIND_HOST)" \
		--http-port "$(VITALSERVER_HTTP_PORT)" \
		--recorders 5 \
		--max-messages 100 \
		--interval 0.02 \
		--replay-batch-size 13 \
		--replay-rate-limit-per-second 50 \
		--max-replay-lag-seconds 30 \
		--assert-app-stable

testkit/recorder-ingress/backpressure: require-testkit-runtime
	RECORDER_INGRESS_SEND_DATA_MODE=spool_and_replay \
	RECORDER_INGRESS_SEND_DATA_REPLAY_ENABLED=1 \
	RECORDER_INGRESS_SEND_DATA_REPLAY_INTERVAL_MS=1000 \
	RECORDER_INGRESS_SEND_DATA_REPLAY_RATE_LIMIT_PER_SECOND=1 \
	$(PYTHON) scripts/recorder_ingress_compose_e2e.py \
		--compose "$(DOCKER_COMPOSE)" \
		--bind-host "$(VITALSERVER_BIND_HOST)" \
		--http-port "$(VITALSERVER_HTTP_PORT)" \
		--recorders 2 \
		--max-messages 10 \
		--interval 0.001 \
		--replay-rate-limit-per-second 1 \
		--max-pending-items 1 \
		--min-spooled-events 1 \
		--min-replayed-events 1 \
		--min-rejected-events 1
