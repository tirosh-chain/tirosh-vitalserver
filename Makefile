DOCKER_COMPOSE ?= docker compose
COMPOSE_ENV_FILE ?=
COMPOSE = $(DOCKER_COMPOSE) $(if $(COMPOSE_ENV_FILE),--env-file $(COMPOSE_ENV_FILE),)

.PHONY: help init build up down restart logs ps shell config update-submodule clean-volumes

help:
	@printf "tirosh-vitalserver commands:\n"
	@printf "  make init             Initialize and update git submodules\n"
	@printf "  make build            Build the VitalServer Docker image\n"
	@printf "  make up               Build and start services in the background\n"
	@printf "  make down             Stop services and keep Docker volumes\n"
	@printf "  make restart          Restart services\n"
	@printf "  make logs             Follow service logs\n"
	@printf "  make ps               Show service status\n"
	@printf "  make shell            Open a shell in the app container\n"
	@printf "  make config           Render the effective Compose config\n"
	@printf "  make update-submodule Update the VitalServer submodule from upstream main\n"
	@printf "  make clean-volumes    Stop services and remove Docker volumes\n"
	@printf "\n"
	@printf "Variables:\n"
	@printf "  VITALSERVER_HTTP_PORT=8080\n"
	@printf "  VITALSERVER_ADMIN_PASSWORD=admin\n"
	@printf "  COMPOSE_ENV_FILE=.env.local\n"
	@printf "  DOCKER_COMPOSE='docker compose'\n"

init:
	git submodule update --init --recursive

build: init
	$(COMPOSE) build

up: init
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

restart: down up

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

shell:
	$(COMPOSE) exec app sh

config:
	$(COMPOSE) config

update-submodule:
	git submodule update --remote --merge vitalserver

clean-volumes:
	$(COMPOSE) down --volumes
