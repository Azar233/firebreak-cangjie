param([switch]$Verify, [switch]$VerifyMagic, [switch]$Run, [string]$MinecraftAssets = $env:MINECRAFT_ASSETS, [string]$ClickSound = $env:FIREBREAK_CLICK_SOUND, [string]$BackgroundMusic = $env:FIREBREAK_BACKGROUND_MUSIC)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $sdk = Join-Path $PSScriptRoot '../.tools/cangjie'
    if (!(Test-Path "$sdk/envsetup.ps1")) { $sdk = $env:CANGJIE_HOME }
    if (!$sdk -or !(Test-Path "$sdk/envsetup.ps1")) { throw 'Cangjie SDK 1.0.5 required. Set CANGJIE_HOME.' }
    . "$sdk/envsetup.ps1"
    # cjpm's build hook owns preparation and runnable output staging.
    $savedAssets = $env:MINECRAFT_ASSETS
    $savedClick = $env:FIREBREAK_CLICK_SOUND
    $savedMusic = $env:FIREBREAK_BACKGROUND_MUSIC
    try {
        if ($MinecraftAssets) { $env:MINECRAFT_ASSETS = $MinecraftAssets }
        if ($ClickSound) { $env:FIREBREAK_CLICK_SOUND = $ClickSound }
        if ($BackgroundMusic) { $env:FIREBREAK_BACKGROUND_MUSIC = $BackgroundMusic }
        & "$sdk/tools/bin/cjpm.exe" build
        if ($LASTEXITCODE -ne 0) { throw 'Firebreak build failed; see build-script-cache for preparation errors.' }
    } finally {
        $env:MINECRAFT_ASSETS = $savedAssets
        $env:FIREBREAK_CLICK_SOUND = $savedClick
        $env:FIREBREAK_BACKGROUND_MUSIC = $savedMusic
    }
    if ($Verify) {
        $previousErrorAction = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & './target/release/bin/main.exe' --verify 2>&1 | Tee-Object -FilePath 'artifacts/p6-checks.log'
            $checkExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previousErrorAction }
        if ($checkExit -ne 0) { throw "Workbench checks failed ($checkExit). See artifacts/p6-checks.log." }
    }
    if ($VerifyMagic) { & './tools/verify-magic.ps1' }
    if ($Run) { & './target/release/bin/main.exe' }
} finally { Pop-Location }
