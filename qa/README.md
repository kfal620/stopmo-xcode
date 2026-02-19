# QA Workflows

## Phase 10 Parity Signoff

Run end-to-end parity checks between CLI and GUI bridge surfaces:

```bash
.venv/bin/python qa/phase10_parity_signoff.py --repo-root /Users/kyle/Documents/Coding/stopmo-xcode
```

Outputs are written under:

- `/Users/kyle/Documents/Coding/stopmo-xcode/qa/reports/phase10_<timestamp>/parity_signoff.md`
- `/Users/kyle/Documents/Coding/stopmo-xcode/qa/reports/phase10_<timestamp>/parity_signoff.json`

The signoff currently checks:

- `status` CLI vs `queue-status` bridge counts
- `dpx-to-prores` CLI vs bridge parity on empty input
- Failure-path parity for `transcode-one` and `suggest-matrix`
- Diagnostics/history/bundle smoke checks
- Config validation and watch preflight smoke checks
