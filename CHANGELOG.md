# Changelog

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

