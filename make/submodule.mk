.PHONY: init update-submodule

init:
	git submodule update --init --recursive

update-submodule:
	git submodule update --remote --merge vendor/vitalserver
