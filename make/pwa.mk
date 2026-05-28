PWA_DIR ?= apps/vitalserver-runtime-pwa
NPM ?= npm

.PHONY: pwa-install pwa-generate-api pwa-check pwa-test pwa-build pwa-dev pwa-preview

pwa-install:
	$(NPM) --prefix $(PWA_DIR) install

pwa-generate-api:
	$(NPM) --prefix $(PWA_DIR) run generate:api

pwa-check:
	$(NPM) --prefix $(PWA_DIR) run check

pwa-test:
	$(NPM) --prefix $(PWA_DIR) test

pwa-build:
	$(NPM) --prefix $(PWA_DIR) run build

pwa-dev:
	$(NPM) --prefix $(PWA_DIR) run dev

pwa-preview:
	$(NPM) --prefix $(PWA_DIR) run preview
