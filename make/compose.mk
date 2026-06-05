.PHONY: app/build app/rebuild app/up app/down app/restart app/logs app/ps app/shell app/config app/clean app/clean/volumes
.PHONY: open
.PHONY: swagger/up swagger/down

COMPOSE_ARGS = \
	--compose "$(COMPOSE)" \
	--bind-host "$(VITALSERVER_BIND_HOST)" \
	--http-port "$(VITALSERVER_HTTP_PORT)" \
	--redis-host "$(VITALSERVER_REDIS_HOST)" \
	--redis-port "$(VITALSERVER_REDIS_PORT)" \
	--trust-proxy "$(VITALSERVER_TRUST_PROXY)"

app/build: repo/init
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- build

app/rebuild: repo/init
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- build app
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- up -d --no-deps --force-recreate app

app/up: repo/init proxy/test
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- up -d
	$(MAKE) proxy/run

app/down:
	$(MAKE) proxy/stop
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- down

app/restart: app/down
	$(MAKE) app/up

app/logs:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- logs -f

app/ps:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- ps

open:
	$(DEVTOOLS_RUNNER) open --port "$(VITALSERVER_PROXY_PORT)"

app/shell:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- exec app sh

app/config:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- config

app/clean/volumes:
	$(MAKE) proxy/stop
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- down --volumes

app/clean:
	$(MAKE) proxy/clean
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- down --volumes --remove-orphans --rmi local

swagger/up:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- --profile swagger up -d --no-deps swagger-ui
	@printf "Swagger UI: http://localhost:$${SWAGGER_UI_PORT:-8082}\n"

swagger/down:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- --profile swagger stop swagger-ui
