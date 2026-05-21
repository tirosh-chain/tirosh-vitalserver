include make/vm/config.mk

# Local VM lifecycle targets: vm-up, vm-start, vm-health, networking, cleanup.
include make/vm/runtime.mk

# Release artifact targets: rootfs, app, pkg, dmg, update bundles.
include make/vm/package.mk

# Installed-runtime inspection targets.
include make/vm/installed.mk
