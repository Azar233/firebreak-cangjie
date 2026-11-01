# Vendored CangjieSDL

Source: https://gitcode.com/CangjieArts/SDL

Base commit: `79afc41fed8436df2dc9fe1ba7046a7ee3d20b93`, package version 0.9.6.
License: MIT; the complete upstream LICENSE is retained.

This source snapshot preserves the workspace's existing window/window_spec changes
(13 added lines, 1 removed line) used for DPI and window behavior. They are recorded
in LOCAL_CHANGES.patch and already applied to src. No nested Git repository or
runtime DLLs are committed. Runtime preparation is in ../../tools/prepare-runtime.ps1
relative to the project root's vendor layout (run it from firebreak/tools).
