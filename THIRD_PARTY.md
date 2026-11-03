# Third-party components

| Component | Version/source | Handling |
|---|---|---|
| CangjieSDL | 0.9.6, commit 79afc41fed8436df2dc9fe1ba7046a7ee3d20b93; https://gitcode.com/CangjieArts/SDL | MIT source snapshot and LICENSE in vendor/SDL; existing local window changes documented |
| SDL3 | 3.4.12; https://github.com/libsdl-org/SDL | Native release downloaded separately, not committed |
| SDL_image | 3.4.6; https://github.com/libsdl-org/SDL_image | Native release downloaded separately, not committed |
| SDL_ttf | 3.2.2; https://github.com/libsdl-org/SDL_ttf | Native release downloaded separately, not committed |
| SDL_mixer | 3.2.4; https://github.com/libsdl-org/SDL_mixer | Official x64 native release, SHA256 `9af526f8defc72ca3b979a6dc4d9e549e5be4dd8db3190cfa8941923a78f73cb`; pinned download with built-in OGG decoding, upstream LICENSE copied beside the executable; binaries not committed |
| Cangjie stdx | 1.0.5.1 | Downloaded to the workspace .tools cache, not committed |
| CangjieMagic | MIT, https://github.com/cangjiepl/CangjieMagic , commit bc4624fac86ad8498b61d7e5f3b1168659bc72b5 | Runtime agent/tool orchestration. prepare-magic.ps1 fetches source separately, adapts the stdx path and adds two public factories for protected streaming constructors. The original HTTP transport is bypassed in favor of verified native HTTPS; upstream LICENSE is copied beside the executable |
| CodeGraph Cangjie | 1.5.0-cangjie-1.0.5.3 | Optional development tool, not committed or shipped with the application |
| Minecraft textures/font | Pinned official Java 1.12.2 legacy Unicode/GUI resources and Java 1.21.1 block/item resources, listed in assets/manifest.json | tools/prepare-minecraft-assets.ps1 prepares the local assets/minecraft cache automatically; optional MINECRAFT_ASSETS override. Original assets and client archives are excluded from Git and are not MIT-licensed |
| UI click / background music | User-provided `click_stereo.ogg` and `Minecraft.ogg` | Existing user files are preserved. Missing files are downloaded locally from official hashed asset objects: click `2fe092579d9637e2d160319820ee08e60a237bb7`, Minecraft/calm1 `50a59a4f56e4046701b758ddbb1c1587efa4cadf`. Audio is not uploaded, redistributed, or MIT-licensed; original rights remain with the relevant owners, including C418 for the music. build.ps1 audio overrides remain available |
| Minecraft grass/dirt textures | Java 1.21.1 official client, SHA1 `30c73b1c5da787909b2f73340419fdf13b9def88` | `tools/prepare-grass-textures.ps1` extracts four textures; client cache and original textures remain excluded from Git |
| README oak-sapling icon | A PNG frame from the application's generated icon, based on the user-provided Minecraft oak sapling | Included as a single README illustration at the user's explicit request; the full resource pack remains excluded |
| Windows WinHTTP | Windows system HTTPS API | Cangjie calls the system DLL for authenticated DeepSeek connectivity checks and streaming chat, using OS certificate validation and disabling redirects; no additional runtime is redistributed |

Retain upstream license notices when packaging native runtime distributions. The
repository contains selected application screenshots for review, not the original
Minecraft resource bundle or a game client. Final distributable resource review
remains part of the delivery checklist.

## Project license and official asset terms

The root LICENSE applies to original Firebreak code and original documentation only. It does not relicense vendor code, Minecraft artwork/fonts/audio, the oak-sapling illustration, or third-party content visible in screenshots.

- Official resource clients: Java 1.12.2 SHA1 `0f275bc1547d01fa5f56ba34bdc87d981ee12daf`; Java 1.21.1 SHA1 `30c73b1c5da787909b2f73340419fdf13b9def88`.
- Downloads use `piston-data.mojang.com` and `resources.download.minecraft.net`; the build verifies SHA1 before extracting the fixed manifest entries. Client jars are not executed or committed.
- [Minecraft Usage Guidelines](https://www.minecraft.net/en-us/usage-guidelines) and [Minecraft EULA](https://www.minecraft.net/en-us/eula) govern Minecraft content. Automatic preparation is a convenience, not an MIT grant or permission to redistribute the original assets.

Not an official Minecraft product. Not approved by or associated with Mojang or Microsoft.
