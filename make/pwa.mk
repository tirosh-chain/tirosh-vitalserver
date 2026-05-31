PWA_DIR ?= apps/vitalserver-runtime-pwa
NPM ?= npm

.PHONY: pwa-install pwa-require-deps pwa-generate-api pwa-check pwa-test pwa-coverage pwa-build pwa-dev pwa-preview

pwa-install:
	$(NPM) --prefix $(PWA_DIR) install

pwa-require-deps:
	@test -d "$(PWA_DIR)/node_modules" || { \
		printf "missing PWA npm dependencies: %s/node_modules\n" "$(PWA_DIR)" >&2; \
		printf "Run 'make pwa-install' on the build machine before packaging.\n" >&2; \
		exit 1; \
	}

pwa-generate-api:
	$(NPM) --prefix $(PWA_DIR) run generate:api

pwa-check:
	$(NPM) --prefix $(PWA_DIR) run check

pwa-test:
	$(NPM) --prefix $(PWA_DIR) test

pwa-coverage:
	$(NPM) --prefix $(PWA_DIR) run coverage

pwa-build: pwa-require-deps
	$(NPM) --prefix $(PWA_DIR) run build

pwa-dev:
	$(NPM) --prefix $(PWA_DIR) run dev

pwa-preview:
	$(NPM) --prefix $(PWA_DIR) run preview
