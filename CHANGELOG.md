# Changelog

## v0.4.0 — P4 constrained candidate planning (2026-11-02)

- Generate up to 14 feasible road-adjacent, target-perimeter and articulation-cell additions while preserving existing treatment and enforcing calibration, target/exclusion and total-budget constraints.
- Rank on 8 shared training scenarios using explicit benefit/cost metrics, then allow 8 disjoint-key holdout scenarios to reject the training winner without selecting a replacement. Preserve failed candidates and avoid global-optimum claims.
- Add menu entry, cancellable background search, map-only preview, labeled unapplied P3 comparison, explicit manual apply/undo and revision invalidation. Export all candidate masks, sample metrics, scenarios and bilingual explanations.
- Include a tested connector-camp example and one planning screenshot. 229 native checks passed (27 new P4 checks plus 202 affected regressions); see docs/P4_PLANNING.md. P5 CangjieMagic integration remains upcoming.

## v0.3.2 — Adaptive modals and clearer book text (2026-11-02)

- Scale menu/book geometry, text, button borders and input targets together in quarter steps from 1x to 3x as window space grows.
- Remove the handbook 0.9x font reduction and dark text shadow; snap glyph geometry to physical pixels while retaining original MC textures and fonts.
- Check 202 native assertions, including five layout sizes through 4K, both languages, DPI pixel alignment, real shadow/no-shadow rendering, fullscreen pointer input and live resize. See docs/MENU_AND_GUIDE.md.

## v0.3.1 — MC menu, bilingual UI and handbook (2026-11-02)

- Add an Esc pause menu with project/display/experiment categories, a clearly disconnected agent information page, safe save/quit choices, and a visible menu button. Cancelled exit restores the original page and draft.
- Add immediate Chinese/English UI and Markdown-report switching, persisted separately in an ignored local language preference. Keep site data, scenarios and numeric exports unchanged.
- Add an eight-page bilingual project/theory handbook using the original MC book texture and page arrows, with font-aware wrapping, keyboard navigation and page bounds.
- Validate 196 native checks: 30 new menu/language/handbook/exit checks and 166 affected regressions. No new runtime dependency; visual quality awaits user review. See docs/MENU_AND_GUIDE.md.

## v0.3.0 — P3 paired evaluation and export (2026-11-02)

- Freeze baseline/site/plan inputs and evaluate identical ignition, seed and rule inputs in cancellable background batches. Revision changes invalidate old tasks and results.
- Separate clearing, burned, remaining and cumulative target-contact metrics; preserve all samples and use explicit weights. A treated ignition is recorded as prevented, never resampled.
- Add synchronized two-pane voxel/map replay for scenario 1, shared camera controls, batch progress and 4/16/32 sample selection.
- Export per-sample CSV, exact parameters/scenarios, frozen project, Markdown report and paired final PNG maps into a new report directory without overwriting existing reports.
- Preserve Float64 project values with 17 significant digits for reproducibility. Project format remains v2.

Validation: 166 native checks passed (24 new P3 checks plus affected P0–P2.1 regressions); see docs/P3_VALIDATION.md. Visual quality and native dialog experience await user review. Grid remains 24×20; P4 budget-constrained recommendations and P5 CangjieMagic integration remain upcoming. TODO remains local-only.

## v0.2.2 — Source-only repository cleanup (2026-11-02)

Remove three generated Magic-probe build-script cache files from Git tracking and
ignore compiler objects/build-script caches. Preserve the already-pushed v0.2.1
history; application logic and P2.1 behavior are unchanged. This is the preferred
source-only baseline for subsequent P3 work.

## v0.2.1 — P2.1 baseline (2026-11-02)

Initial Git-managed snapshot of the Minecraft-style forest fire planning workbench:

- Editable site, separate treatment plan, protected/forbidden areas, calibration,
  budget constraints, safe project save/load, and undo/redo.
- Original-texture top-down map, parchment frame and 3D view.
- Four-neighbor connectivity, target-perimeter paths, deterministic finite spread,
  fixed playback clock and snapshot replay.
- Progressive canopy removal, charred stumps and ash; original site remains intact.
- Optional project-local CodeGraph navigation with documented resolution limits.
- CangjieSDL source snapshot, pinned native dependency preparation and external
  Minecraft-resource input for reproducible checkout builds.

P3 multi-scenario paired evaluation and report export are next, not implemented in
this release. The AI interaction design is accepted for P5: a computer terminal
main panel, a slash-key quick input, one shared conversation, streaming answers,
actual tool status, and map-based preview/application. The local TODO is excluded
from Git by explicit user request.

Future completed phases are committed, pushed and annotated with a version tag
only after their relevant checks pass. See AGENTS.md for the synchronization rule.

Validation: source-only staged checkout built successfully with externally supplied SDK/resources; all 142 native checks passed. See docs/REPOSITORY.md.

