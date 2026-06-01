# Agent Guidelines

## Core Philosophy

VitalServer code must be simple, explicit, and predictable.

State must not be guessed. The owner of a state must provide it explicitly, and consumers must only use, format, or display that state. Missing, invalid, and failed states are different meanings and must stay different in code.

The architecture must make domain meaning, role boundaries, dependency direction, and layer responsibility easy to read.

## Repository Policy

This repository is a monorepo. Changes must respect package boundaries and avoid unrelated cross-package edits.

Documentation is part of the product. Important architectural decisions, repeated failure patterns, and troubleshooting lessons must be written close to the relevant context. Troubleshooting entries should explain symptom, cause, fix direction, and prevention principle.

Prefer one focused change per commit. When code changes introduce or clarify an operational rule, update the related documentation in the same change.

## Fallback Boundaries

Fallback must not create, infer, or hide state.

Do not use fallback at contract, repository, domain, recovery, update, API command, or observability boundaries. Missing, invalid, failed, stale, and zero/empty must remain distinct.

Allowed fallback is limited to display labels, input presets, documented config defaults, explicit migrations, and reported degraded operation.

## Purity Boundaries

Pure code computes from complete explicit inputs only. It must not read external state or create domain state from absence.

Stateless code may orchestrate calls and map explicit results, but must not cache hidden state or convert dependency failure into success.

Stateful code must declare owned state, expose it through explicit contracts, and report read/write/decode/permission failures.

## HAVE TO

- Keep code simple, explicit, and domain-readable.
- Follow role and responsibility boundaries.
- Follow Clean Architecture layer direction.
- Model domain concepts with DDD language.
- Keep dependencies flowing inward, not across or backward.
- Let each layer do its own job.
- Let state owners provide state through explicit contracts.
- Make failures visible and typed enough to act on.
- Use TDD or focused tests when changing domain behavior, contracts, or update flow.
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
- Must not make code clever when a direct contract would be clearer.
