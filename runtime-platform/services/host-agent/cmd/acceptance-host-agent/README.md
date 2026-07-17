# Acceptance Host Agent

This command is a test-only composition root. It wires the real Host Agent SQLite repository, HTTP facade, and Guest Runtime HTTP adapter to an explicit deterministic provider test double.

It is not a product binary and is never selected by the product Host Agent command. The acceptance harness uses it to prove that provider lifecycle observation and Guest transport are separate: after an explicit test-provider stop result, the Host facade must return typed unavailable even while the independently running Guest test process can still answer direct requests.

It can additionally expose an explicit `staged`, `failed`, or `unavailable` update bootstrap result and write an acceptance-only handoff marker. In `verified-staged-bundle` mode it composes the production `StagedBundleBootstrapper` with explicit bundle, staging, and trust-store paths. This proves C29–C31 durable handoff/restart behavior without pretending that a test marker performs package activation.
