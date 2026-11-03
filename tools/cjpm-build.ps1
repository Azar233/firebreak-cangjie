param([Parameter(Mandatory=$true)][ValidateSet('Prepare','Finalize')][string]$Stage)
$ErrorActionPreference = 'Stop'
# Windows PowerShell may inherit PowerShell 7's module search path from cjpm.
$nativeModules = Join-Path $PSHOME 'Modules'
$desktopModules = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'WindowsPowerShell/Modules'
$env:PSModulePath = $nativeModules + ';' + $desktopModules + ';' + $env:PSModulePath
$project = Split-Path $PSScriptRoot -Parent
Push-Location $project
try {
    if ($Stage -eq 'Prepare') {
        $ClickSound = $env:FIREBREAK_CLICK_SOUND
        $BackgroundMusic = $env:FIREBREAK_BACKGROUND_MUSIC
        & './tools/prepare-runtime.ps1'
        & './tools/prepare-magic.ps1'
        & './tools/prepare-minecraft-assets.ps1'
        & './tools/prepare-grass-textures.ps1'
        # User-provided audio stays in the same ignored local resource tree.
        New-Item -ItemType Directory -Path 'assets/minecraft/sounds' -Force | Out-Null
        if ($ClickSound) { Copy-Item -LiteralPath $ClickSound -Destination 'assets/minecraft/sounds/click_stereo.ogg' -Force }
        if ($BackgroundMusic) { Copy-Item -LiteralPath $BackgroundMusic -Destination 'assets/minecraft/sounds/Minecraft.ogg' -Force }
    } else {
        $found = $false
        foreach ($profile in @('release', 'debug')) {
            $bin = Join-Path $project "target/$profile/bin"
            $binary = Join-Path $bin 'firebreak.exe'
            if (!(Test-Path -LiteralPath $binary)) { continue }
            $found = $true
            $entry = Join-Path $bin 'main.exe'
            Copy-Item -LiteralPath $binary -Destination $entry -Force
            & './tools/set-app-icon.ps1' -SourceImage 'assets/minecraft/textures/block/oak_sapling.png' -Executable $entry
            Get-ChildItem -LiteralPath 'vendor/SDL/.sdl3' -Filter '*.dll' | Copy-Item -Destination $bin -Force
            Get-ChildItem -LiteralPath "target/$profile/magic" -Filter '*.dll' -Recurse | Copy-Item -Destination $bin -Force
            Get-ChildItem -LiteralPath '../.tools/stdx-1.0.5.1/windows_x86_64_cjnative/dynamic/stdx' -Filter '*.dll' | Copy-Item -Destination $bin -Force
            Copy-Item -LiteralPath '../.reference/CangjieMagic/LICENSE' -Destination (Join-Path $bin 'CangjieMagic-LICENSE.txt') -Force
            Copy-Item -LiteralPath 'vendor/SDL/.sdl3/SDL3_mixer-LICENSE.txt' -Destination (Join-Path $bin 'SDL3_mixer-LICENSE.txt') -Force
        }
        if (!$found) { throw 'No executable under target/release/bin or target/debug/bin. Use the default cjpm target directory.' }
    }
} finally { Pop-Location }
