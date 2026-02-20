# GUI Phase 1 Design System Foundation

Phase 1 objective: introduce shared UI primitives and migrate one production screen without removing features.

## Shared Components Added

Source:

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/DesignSystem.swift`

Components:

1. `StopmoUI` token namespace
- Spacing scale (`xxs`, `xs`, `sm`, `md`, `lg`)
- Corner radius tokens (`card`, `chip`)
- Width token (`keyColumn`)

2. `StatusTone`
- Semantic visual tones for neutral/success/warning/danger states.

3. `ScreenHeader`
- Consistent page title/subtitle structure with optional trailing actions.

4. `SectionCard`
- Structured content container for grouped sections.

5. `StatusChip`
- Compact status indicator for availability/health/readiness states.

6. `KeyValueRow`
- Standardized key/value line with optional semantic tone.

7. `LabeledPathField`
- Reusable labeled path input with browse button and help tooltip.

8. `EmptyStateCard`
- Consistent empty-state presentation for missing data.

## Migrated Screen (Reference Implementation)

- `/Users/kyle/Developer/stopmo-xcode/macos/StopmoXcodeGUI/Sources/StopmoXcodeGUI/SetupView.swift`

Migrated areas:
1. Setup screen title and copy via `ScreenHeader`.
2. Workspace section layout and path controls via `SectionCard` + `LabeledPathField`.
3. Workspace access status via `StatusChip`.
4. Runtime health rows via `KeyValueRow` + `StatusChip`.
5. Dependency checks, config validation, and watch preflight status via semantic chips.
6. No-loss action set preserved:
   - Choose Workspace
   - Check Runtime Health
   - Load Config
   - Save Config
   - Validate Config
   - Watch Preflight

## Validation

1. `swift build` passes in `macos/StopmoXcodeGUI`.
2. `swift test` passes with Phase 0 smoke tests unchanged.
3. Xcode wrapper regenerated so new source file is indexed:
   - `StopmoXcodeGUI.xcodeproj/project.pbxproj`
