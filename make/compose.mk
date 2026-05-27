.PHONY: build app-build app-rebuild up down restart logs ps shell config clean clean-volumes
.PHONY: open
.PHONY: swagger swagger-down

COMPOSE_ARGS = \
	--compose "$(COMPOSE)" \
	--bind-host "$(VITALSERVER_BIND_HOST)" \
	--http-port "$(VITALSERVER_HTTP_PORT)" \
	--redis-host "$(VITALSERVER_REDIS_HOST)" \
	--redis-port "$(VITALSERVER_REDIS_PORT)" \
	--trust-proxy "$(VITALSERVER_TRUST_PROXY)"

build: init
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- build

app-build: init
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- build app

app-rebuild: init
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- build app
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- up -d --no-deps --force-recreate app

up: init proxy-test
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- up -d
	$(MAKE) proxy-run

down:
	$(MAKE) proxy-stop
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- down

restart: down
	$(MAKE) up

logs:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- logs -f

ps:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- ps

open:
	$(DEVTOOLS_RUNNER) open --port "$(VITALSERVER_PROXY_PORT)"

shell:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- exec app sh

config:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- config

clean-volumes:
	$(MAKE) proxy-stop
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- down --volumes

clean:
	$(MAKE) proxy-clean
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- down --volumes --remove-orphans --rmi local

swagger:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- --profile swagger up -d --no-deps swagger-ui
	@printf "Swagger UI: http://localhost:$${SWAGGER_UI_PORT:-8082}\n"

swagger-down:
	$(DEVTOOLS_RUNNER) compose $(COMPOSE_ARGS) -- --profile swagger stop swagger-ui
