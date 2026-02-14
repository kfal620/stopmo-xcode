# Agent Environment Instructions

Use the project virtual environment for all Python commands in this repo.

## Environment

- Preferred environment path: `/Users/kyle/Documents/Coding/stopmo-xcode/.venv`
- Run Python tooling with explicit venv binaries:
  - `.venv/bin/python`
  - `.venv/bin/pip`
  - `.venv/bin/pytest`

## Bootstrap if Missing

If `.venv` does not exist, create and initialize it before running Python tasks:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -e ".[dev]"
```

Use additional extras only when needed (for example `.[watch,raw,ocio,io]`).
