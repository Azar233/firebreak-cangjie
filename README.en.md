# Firebreak · 断火线

<p align="center">
  <img src="assets/readme/oak-sapling.png" width="192" alt="Firebreak application icon: oak sapling">
</p>

<p align="center">
  A forest fire planning sandbox built with Cangjie, SDL3 and GPU voxel rendering.<br>
  Map a site, design firebreaks, and compare fire spread and costs under matched ignition scenarios.
</p>

<p align="right"><a href="README.md">简体中文</a> · English</p>

<p align="center">
  <img src="https://img.shields.io/badge/Cangjie-1.0.5-3277AE?style=flat-square" alt="Cangjie 1.0.5">
  <img src="https://img.shields.io/badge/SDL-3-568B42?style=flat-square" alt="SDL 3">
  <img src="https://img.shields.io/badge/GPU-D3D11-AC7136?style=flat-square" alt="GPU D3D11">
  <img src="https://img.shields.io/badge/platform-Windows_x64-555555?style=flat-square" alt="Windows x64">
</p>

<p align="center">
  <a href="#features">Features</a> · <a href="#screenshots">Screenshots</a> · <a href="#run">Run</a> · <a href="#technology-and-docs">Technology &amp; docs</a>
</p>

## Features

- **Site editing:** 3D sandbox and textured overhead map, reference images, land annotations, protected targets, exclusion zones, and undo/redo.
- **Fire experiments:** inspect forest connectivity, configure ignition and spread, step through simulations or replay snapshots.
- **Paired comparisons:** evaluate baseline and treatment plans using matched scenarios and seeds; inspect simulated losses, target contact and treatment costs.
- **Budget planning:** preview a finite set of candidate treatments, apply them manually, and export reports and maps.
- **Minecraft-inspired interaction:** pixel textures, parchment maps, a book-style handbook, Chinese/English UI and optional smooth lighting.

## Screenshots

### 3D site

Edit the forest, roads and protected areas in one navigable scene. Grass uses the meadow tint `#83BB6D`.

![3D planning workbench with voxel forest, roads, a building and protected areas](artifacts/meadow-grass-workbench.png)

### Overhead map

Block textures remain visible while zooming and panning for local inspection and annotation.

![Zoomed parchment map showing tree canopies, roads and site cells](artifacts/map-navigation.png)

### Plan comparison

Both views share navigation and replay time. Replay shows one scenario; summary metrics cover the entire evaluated sample set.

![Baseline and treatment burnout states with aggregated comparison metrics](artifacts/p3-comparison.png)

## Run

Requires Windows x64, Cangjie SDK **1.0.5**, and a Minecraft resource directory containing `textures/` and `font/`.

```powershell
$env:CANGJIE_HOME = 'C:\path\to\cangjie'
$env:MINECRAFT_ASSETS = 'D:\path\to\minecraft-assets'
.\build.ps1 -Run
```

The build script prepares pinned stdx/SDL dependencies and verifies/caches the grass texture source. Original Minecraft assets are excluded from this repository. The first build requires internet access. After building, launch with `run.cmd`.

Open the [connector camp example](examples/connector-camp.firebreak), edit a treatment strip, then choose Fire Trial or Compare Plans. **Esc** opens the menu, **H** toggles canopies; right-drag rotates, middle-drag pans, and the wheel zooms.

## Technology and docs

Cangjie implements application logic, simulation and graphics host code. SDL3 handles the window and UI. D3D11/HLSL performs chunk skipping, voxel ray traversal and surface shading on the GPU. Run `./build.ps1 -Verify` for native logic and GPU checks.

The application uses percolation connectivity and discrete spread for relative plan comparisons. The planning grid is **24×20**, with a simplified four-neighbor, wind-free model. Results support teaching and model-based comparisons, not real wildfire prediction. The large-forest example is a separate rendering diagnostic.

Technical documents are primarily in Chinese: [Model](docs/P2_MODEL.md) · [Evaluation](docs/P3_EVALUATION.md) · [Budget planning](docs/P4_PLANNING.md) · [GPU renderer](docs/GPU_RENDERING.md) · [Smooth lighting](docs/SMOOTH_LIGHTING.md) · [Third-party resources](THIRD_PARTY.md)
