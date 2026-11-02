# Third-party components

| Component | Version/source | Handling |
|---|---|---|
| CangjieSDL | 0.9.6, commit 79afc41fed8436df2dc9fe1ba7046a7ee3d20b93; https://gitcode.com/CangjieArts/SDL | MIT source snapshot and LICENSE in vendor/SDL; existing local window changes documented |
| SDL3 | 3.4.12; https://github.com/libsdl-org/SDL | Native release downloaded separately, not committed |
| SDL_image | 3.4.6; https://github.com/libsdl-org/SDL_image | Native release downloaded separately, not committed |
| SDL_ttf | 3.2.2; https://github.com/libsdl-org/SDL_ttf | Native release downloaded separately, not committed |
| Cangjie stdx | 1.0.5.1 | Downloaded to the workspace .tools cache, not committed |
| CangjieMagic | bc4624fac86ad8498b61d7e5f3b1168659bc72b5 | Optional development probe; prepare-magic.ps1 fetches source separately |
| CodeGraph Cangjie | 1.5.0-cangjie-1.0.5.3 | Optional development tool, not committed or shipped with the application |
| Minecraft textures/font | User-provided resource files listed in assets/manifest.json | Original resources excluded from Git; provide MINECRAFT_ASSETS for a fresh build |
| Minecraft grass/dirt textures | Java 1.21.1 official client, SHA1 `30c73b1c5da787909b2f73340419fdf13b9def88` | `tools/prepare-grass-textures.ps1` extracts four textures; client cache and original textures remain excluded from Git |
| README oak-sapling icon | A PNG frame from the application's generated icon, based on the user-provided Minecraft oak sapling | Included as a single README illustration at the user's explicit request; the full resource pack remains excluded |

Retain upstream license notices when packaging native runtime distributions. The
repository contains selected application screenshots for review, not the original
Minecraft resource bundle or a game client. Final distributable resource review
remains part of the delivery checklist.
