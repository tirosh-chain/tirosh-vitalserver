.PHONY: repo/init repo/update-submodule

repo/init:
	git submodule update --init --recursive

repo/update-submodule:
	git submodule update --remote --merge vendor/vitalserver
