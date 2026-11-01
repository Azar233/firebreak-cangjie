# Optional CodeGraph navigation

Keep the existing source-reading, precise-change and verification rules. CodeGraph
is an optional development tool, not an application dependency or a prerequisite
for building/testing. Follow higher-priority instructions to use rg first.

For cross-file exploration, callers/callees and candidate impact ranges, use:

```powershell
.\tools\codegraph.ps1 -Action Callers -Names App.refreshExperimentView -Json
.\tools\codegraph.ps1 -Action Impact -Names fireDisplayMaterial -Json
.\tools\codegraph.ps1 -Action Affected -Names src/scene.cj -Json
.\tools\codegraph.ps1 -Scope SDL -Action Query -Names Surface -Json
```

The wrapper pins the assessed version, syncs live sources before querying, disables
telemetry/update checks for the child process, and supports separate Project/SDL/
Magic indexes. If unavailable, continue with rg and direct reads; do not install
or configure global MCP/AGENTS as a side effect of ordinary work.

Use qualified method names to disambiguate. The assessed parser misses real calls
through some optional/coalesced receivers (notably simulationAction -> r.advance).
An empty query is not proof of no callers. Confirm important paths with rg and
source reads. Impact results are candidates, not a guarantee of actual effects.
Affected uses the project's verify*.cj convention; never use it to automatically
skip required checks or replace the native --verify entry point. See
docs/CODEGRAPH_ASSESSMENT.md for measured limits.

# Milestone Git synchronization

The user authorized committing and pushing a version after each completed phase.
After relevant checks pass, commit scoped source/docs changes, push main, and push
an annotated milestone tag (P2.1=v0.2.1, P3=v0.3.0, and so on). Report the commit,
tag and remote synchronization result. Do not force push, include unrelated work,
or label incomplete/failed work as a completed milestone. If remote access fails,
preserve the local commit and report the pending push accurately.

TODO.md is local-only by explicit user request. Maintain it locally but never
force-add or upload it. Record release state and reproduction instructions in
tracked documentation instead. Keep credentials, caches, binaries and original
Minecraft resource files out of Git.
