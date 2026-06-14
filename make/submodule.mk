.PHONY: repo/init repo/update-submodule repo/verify-submodule repo/verify-submodule-candidate repo/verify-submodule-candidate/remote

repo/init:
	git submodule update --init --recursive

repo/update-submodule:
	git submodule update --remote --merge vendor/vitalserver

repo/verify-submodule:
	$(DEVTOOLS_RUNNER) verify-upstream-vitalserver --mode approved

repo/verify-submodule-candidate:
	$(DEVTOOLS_RUNNER) verify-upstream-vitalserver --mode candidate

repo/verify-submodule-candidate/remote:
	$(DEVTOOLS_RUNNER) verify-upstream-vitalserver --mode candidate --require-remote-commit
