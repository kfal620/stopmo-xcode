# Commenting Standards

This project uses comments to preserve intent and invariants, not to narrate syntax.

## Goals

- Explain *why* a behavior exists, especially around deterministic pipeline guarantees.
- Document contracts at module/type/function boundaries.
- Keep comments concise and stable under normal refactors.

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
- Avoid stale implementation-detail comments that are likely to drift.
- Avoid broad block comments where precise docstrings are better.

## PR Checklist

- Touched modules have module/type/function docs where applicable.
- New complex logic includes a short rationale comment.
- No redundant or line-by-line narration comments were introduced.
