# Agent Guidelines

## Core Philosophy

VitalServer code must be simple, explicit, and predictable.

State must not be guessed. The owner of a state must provide it explicitly, and consumers must only use, format, or display that state. Missing, invalid, and failed states are different meanings and must stay different in code.

The architecture must make domain meaning, role boundaries, dependency direction, and layer responsibility easy to read.

Host owns runtime/process/filesystem state. Guest consumes explicit Host contracts only.

## Repository Policy

This repository is a monorepo. Changes must respect package boundaries and avoid unrelated cross-package edits.

Documentation is part of the product. Important architectural decisions, repeated failure patterns, and troubleshooting lessons must be written close to the relevant context. Troubleshooting entries should explain symptom, cause, fix direction, and prevention principle.

Repeated operational failures must be promoted into troubleshooting docs with symptom, cause, fix direction, and prevention.

VM build is product compile: kernel panic, guest boot failure, rootfs proof failure, and runtime smoke failure are compile failures to expose explicitly, not conditions to hide or bypass.

VM compile failures must report explicit proof context: runId when available, failing stage, failure reason or matched pattern, and relevant artifact/log paths.

Prefer one focused change per commit. When code changes introduce or clarify an operational rule, update the related documentation in the same change.

## Fallback Boundaries

Fallback must not create, infer, or hide state.

Do not use fallback at contract, repository, domain, recovery, update, API command, or observability boundaries. Missing, invalid, failed, stale, and zero/empty must remain distinct.

Absence, decode failure, permission failure, and dependency failure must not become empty/default success.

Build/test/devtools probes may fail fast on external symptoms, but they must not convert logs, missing files, stale documents, or probe failures into domain/runtime state.

Build/devtools may classify external logs as compile/test failure evidence, but those classifications must stay in diagnostics and must not become runtime/domain state.

Optional behavior must be explicitly configured; missing or unreadable configuration must be reported as unavailable/error, not silently treated as disabled.

Allowed fallback is limited to display labels, input presets, documented config defaults, explicit migrations, and reported degraded operation.

## Purity Boundaries

Pure code computes from complete explicit inputs only. It must not read external state or create domain state from absence.

Stateless code may orchestrate calls and map explicit results, but must not cache hidden state or convert dependency failure into success.

Stateful code must declare owned state, expose it through explicit contracts, and report read/write/decode/permission failures.

## Layer Boundaries

Contracts define explicit state, event, command, and document types shared across layers. Contracts must preserve missing, invalid, failed, stale, zero, and empty meanings.

Domain/Core defines pure policy, state machines, transition rules, guards, and invariants. Domain/Core consumes complete explicit inputs only and must not read Host, Guest, filesystem, process, network, logs, or command output state.

Application/Usecase/Workflow orchestrates an operation. It reads explicit state through ports, calls Domain/Core policy, executes returned commands through ports, creates explicit events from results, and persists operation state when required. Workflow may sequence steps, but must not infer state.

Adapters, HostCLI, packaging scripts, repositories, and infrastructure own external reads and writes. They must report explicit typed results and failures to the inward layers instead of converting dependency failure into success.

Presentation/UI formats explicit state for humans. It must not create domain state, decide domain transitions, or repair missing provider contracts.

State machines that manage operation transitions must define states, events, guards, commands/effects, invariants, and persisted state documents when persistence is part of the operation. State machines return decisions; they do not perform side effects.

## HAVE TO

- Keep code simple, explicit, and domain-readable.
- Follow role and responsibility boundaries.
- Follow Clean Architecture layer direction.
- Model domain concepts with DDD language.
- Keep dependencies flowing inward, not across or backward.
- Let each layer do its own job.
- Define state transitions with explicit states, events, guards, commands/effects, and invariants when operation order matters.
- Keep state machines and transition policy pure and inside Domain/Core.
- Keep side effects in Application/Usecase/Workflow ports or adapters.
- Let state owners provide state through explicit contracts.
- Make failures visible and typed enough to act on.
- Use TDD or focused tests when changing domain behavior, contracts, parsing/decoding, recovery, settings, or update flow.
- Prefer deleting fallback logic over preserving unreleased legacy behavior.
- Record important failure patterns in troubleshooting docs.

## MUST NOT

- Must not infer state from logs, probes, filenames, old command output, or absence of data.
- Must not hide read, permission, decode, or contract failures as empty values or defaults.
- Must not let UI create domain state.
- Must not let Host guess Guest internals.
- Must not add compatibility branches for unreleased behavior unless there is an explicit migration.
- Must not let infrastructure concerns leak into domain models.
- Must not use fallback logic to compensate for a missing provider contract.
- Must not mix layer responsibilities for convenience.
- Must not let adapters, shell scripts, or UI own domain transition rules.
- Must not advance an operation from missing, invalid, failed, stale, or unknown state without an explicit transition rule.
- Must not make code clever when a direct contract would be clearer.
