.PHONY: compose/build compose/rebuild compose/up compose/down compose/restart compose/logs compose/ps compose/shell compose/config compose/clean compose/clean/volumes compose/open
.PHONY: swagger/up swagger/down

COMPOSE_ARGS = \
	--compose "$(COMPOSE)" \
	--bind-host "$(VITALSERVER_BIND_HOST)" \
	--http-port "$(VITALSERVER_HTTP_PORT)" \
	--redis-host "$(VITALSERVER_REDIS_HOST)" \
	--redis-port "$(VITALSERVER_REDIS_PORT)" \
	--trust-proxy "$(VITALSERVER_TRUST_PROXY)"

compose/build: repo/init
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- build

compose/rebuild: repo/init
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- build app
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- up -d --no-deps --force-recreate app

compose/up: repo/init proxy/test
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- up -d
	$(MAKE) proxy/run

compose/down:
	$(MAKE) proxy/stop
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- down

compose/restart: compose/down
	$(MAKE) compose/up

compose/logs:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- logs -f

compose/ps:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- ps

compose/open:
	$(DEVTOOLS_RUNNER) open --port "$(VITALSERVER_PROXY_PORT)"

compose/shell:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- exec app sh

compose/config:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- config

compose/clean/volumes:
	$(MAKE) proxy/stop
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- down --volumes

compose/clean:
	$(MAKE) proxy/clean
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- down --volumes --remove-orphans --rmi local

swagger/up:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- --profile swagger up -d --no-deps swagger-ui
	@printf "Swagger UI: http://localhost:$${SWAGGER_UI_PORT:-8082}\n"

swagger/down:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- --profile swagger stop swagger-ui
