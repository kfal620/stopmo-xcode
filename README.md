# FrameRelay

FrameRelay is a standalone macOS app for deterministic stop-motion ingest and delivery.
Its primary interface is the SwiftUI desktop app bundle (`FrameRelay.app`), backed by the same
deterministic RAW -> LogC3/AWG pipeline used in CLI workflows.

## Download

- Latest release: [Releases (latest)](../../releases/latest)
- All releases: [Releases](../../releases)
- Release packaging/signing/notarization details: `macos/StopmoXcodeGUI/RELEASE.md`

## Quick Start (macOS App)

1. Download the latest DMG from Releases.
2. Launch `FrameRelay.app`.
3. In `Configure`, load or edit your project config.
4. In `Capture`, start watch/capture monitoring.
5. In `Deliver`, run day-wrap ProRes delivery when ready.

## Main Features

- Deterministic RAW processing pipeline (shot-stable WB/exposure policy).
- Queue-backed crash-safe processing and resume behavior.
- GUI surfaces for health checks, watch state, triage, diagnostics, and delivery.
- Batch DPX -> ProRes delivery workflows.
- Config + operation parity between GUI bridge and CLI commands.

## System Notes

- Standalone app packaging is Developer ID signed + notarized (non-App-Store).
- Runtime payloads are bundled per architecture (`arm64`, `x86_64`).
- If macOS warns on first launch, use standard Gatekeeper approval flow and run notarized release artifacts.

## Troubleshooting

- Open `Configure > Workspace & Health` to check environment/runtime status.
- Use `Triage > Diagnostics` to inspect logs and export diagnostics bundles.
- For release build and notarization details, see `macos/StopmoXcodeGUI/RELEASE.md`.

## Documentation

- GUI project docs: `macos/StopmoXcodeGUI/README.md`
- GUI release/distribution docs: `macos/StopmoXcodeGUI/RELEASE.md`
- Architecture notes: `docs/architecture.md`
- Interpretation contract: `docs/interpretation-contract.md`
- GUI phase docs: `docs/gui-phase13-pipeline-surfaces.md`

## CLI And Developer Docs

- CLI/developer guide: `docs/cli.md`
- Contributor workflow: `CONTRIBUTING.md`
- Agent workflow rules: `AGENTS.md`

## Brand vs Internal Namespace

- Product/app brand is **FrameRelay**.
- Legacy internal namespaces are intentionally still in place for compatibility during this migration:
  - Python module/package paths: `stopmo_xcode`
  - Swift target/module names: `StopmoXcodeGUI`
  - Swift design token namespace: `StopmoUI`
- CLI transition:
  - preferred command: `framerelay`
  - legacy command (still supported, deprecated): `stopmo-xcode`
- Env var transition:
  - preferred prefix: `FRAMERELAY_*`
  - legacy prefix (still supported, deprecated): `STOPMO_XCODE_*`
- A deeper internal namespace rename is tracked as a separate future migration to minimize regression risk in this release.
