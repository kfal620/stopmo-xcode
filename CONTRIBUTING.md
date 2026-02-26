# Contributing

Thanks for contributing to `stopmo-xcode`.

## Where To Start

- Product overview and user-facing install/run: `README.md`
- CLI/developer setup and commands: `docs/cli.md`
- Agent workflow and subsystem test matrix: `AGENTS.md`
- macOS GUI subproject guidance: `macos/StopmoXcodeGUI/AGENTS.md`

## Development Flow

1. Refresh local venv and install dev deps:
   - `python3 -m venv --clear .venv`
   - `.venv/bin/python -m pip install --upgrade pip`
   - `.venv/bin/python -m pip install -e ".[dev]"`
2. Run tests:
   - `.venv/bin/python -m pytest -q`
3. Run focused subsystem tests for touched code paths (see `AGENTS.md`).
4. If changing CLI/GUI bridge parity behavior, run:
   - `.venv/bin/python qa/phase10_parity_signoff.py --repo-root "$PWD"`

## Pull Request Expectations

- Keep docs/config/tests updated with behavior changes.
- Preserve deterministic pipeline invariants documented in `docs/interpretation-contract.md`.
- Include concise test notes in PR descriptions (what ran, what changed).
