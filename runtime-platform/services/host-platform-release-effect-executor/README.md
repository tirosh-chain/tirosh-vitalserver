# Host Platform Release Effect Executor

This is the release-owned C26 effect executable for the final `host-platform`
layer. It verifies the staged archive again, converts C67's selected
compare-and-swap transition to C68, and invokes only the already-installed
Host Installation Manager and active `current/installation-manifest.json`
selected at C67's platform-fixed stable paths. The manager verifies that this
manifest resolves through `current` to the declared active C48 before it reads
or writes C68 operation state.

It does not unpack a Host release, change `current`, stop services, or call a
platform package manager. Those effects and C68 state belong to the Host
Installation Manager. A process exit is not a successful C55 result: only a
correlated terminal C68 operation can produce C55 `succeeded`.
