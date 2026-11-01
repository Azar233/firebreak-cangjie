# Repository and milestone workflow

Repository: https://github.com/Azar233/firebreak-cangjie (private).

The repository root is the firebreak project, not the surrounding multi-project
workspace. Current source-only baseline: P2.1, version v0.2.2. Initial import was
v0.2.1; a follow-up removes generated Magic-probe build-script cache files without
rewriting pushed history. See CHANGELOG.md.

TODO.md is intentionally local-only and ignored. Maintain release notes and model
assumptions in tracked docs. Each completed phase is checked, committed and pushed
with an annotated version tag. Do not force push or claim incomplete phases as
finished. GitHub Releases are not created automatically; tags provide the version
synchronization requested by the user.

Source-only checkout verification (2026-11-02):

- Exported the staged file set into a fresh directory using git checkout-index.
- No native DLLs, original Minecraft resource files, SDK, TODO or build outputs
  were present in that export.
- Supplied the installed SDK through CANGJIE_HOME and original resources through
  the explicit -MinecraftAssets argument.
- Prepared pinned stdx and SDL native dependencies with checksum verification.
- Built the fresh copy and passed all 142 native logic/resource/position checks.

The fresh build exercises the vendored CangjieSDL snapshot, not the neighboring
soft-cat project. Upstream/local source details and native dependency versions are
in THIRD_PARTY.md. Existing whitespace in the inherited source snapshot is kept;
it is not an application correctness failure or an unrecorded source rewrite.

Do not commit credentials, local agent configuration, runtime binaries, resource
bundles or caches. The private repository contains source, instructions, selected
verification logs and application screenshots.
