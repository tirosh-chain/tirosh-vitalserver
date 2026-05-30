# Agent Guidelines

## Core Philosophy

VitalServer code must be simple, explicit, and predictable.

State must not be guessed. The owner of a state must provide it explicitly, and consumers must only use, format, or display that state. Missing, invalid, and failed states are different meanings and must stay different in code.

The architecture must make domain meaning, role boundaries, dependency direction, and layer responsibility easy to read.

## Repository Policy

This repository is a monorepo. Changes must respect package boundaries and avoid unrelated cross-package edits.

Documentation is part of the product. Important architectural decisions, repeated failure patterns, and troubleshooting lessons must be written close to the relevant context. Troubleshooting entries should explain symptom, cause, fix direction, and prevention principle.

Prefer one focused change per commit. When code changes introduce or clarify an operational rule, update the related documentation in the same change.

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
