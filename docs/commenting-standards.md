# Commenting Standards

This project uses comments to preserve intent and invariants, not to narrate syntax.

## Goals

- Explain *why* a behavior exists, especially around deterministic pipeline guarantees.
- Document contracts at module/type/function boundaries.
- Keep comments concise and stable under normal refactors.

## Bad Vs Good

- Bad: `Return queue snapshot.`
  Good: `Capture the queue state shape consumed by polling clients without exposing database rows directly.`
- Bad: `Write preview image.`
  Good: `Persist a lightweight preview artifact so the GUI can inspect pipeline output without opening DPX masters.`
- Bad: `Data/view model for queue job record.`
  Good: `Bridge-facing queue item model shared by triage, monitoring, and delivery screens.`
- Bad: `Enumeration for operation status.`
  Good: `Lifecycle states the GUI uses to distinguish cancellable work from terminal outcomes.`

Prefer one sentence, but make it about contract, invariant, ownership, or compatibility. Delete comments that cannot justify their existence at that level.

## Python (`src/stopmo_xcode`)

- Add a module docstring to each module.
- Add docstrings to top-level classes and top-level functions.
- Add method docstrings for non-trivial behavior:
  - state transitions,
  - concurrency/cancellation behavior,
  - payload validation and compatibility rules,
  - formula-based color/exposure calculations.
- Add inline comments only where intent is not obvious.

## Swift (`macos/StopmoXcodeGUI/Sources`)

- Add `///` docs for top-level types (`struct`, `enum`, `class`, `protocol`).
- Add `///` docs for non-obvious methods (async orchestration, reducers, bridge calls).
- Use `// MARK:` sections in large files for discoverability.
- Prefer comments that describe contracts and UI/backend coupling decisions.

## Anti-Patterns

- Avoid comments that restate obvious code behavior.
- Avoid leading with generic verbs like `Return`, `Write`, `Load`, or `Convert` unless the rest of the sentence explains the semantic contract.
- Avoid placeholder type docs such as `Data/view model for...`, `Enumeration for...`, or `Service type for...`.
- Avoid stale implementation-detail comments that are likely to drift.
- Avoid broad block comments where precise docstrings are better.

## PR Checklist

- Touched modules have module/type/function docs where applicable.
- New complex logic includes a short rationale comment.
- No redundant or line-by-line narration comments were introduced.
