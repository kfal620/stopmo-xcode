"""Module launcher for `python -m stopmo_xcode` CLI entrypoint."""

from .cli import main

if __name__ == "__main__":
    raise SystemExit(main())
