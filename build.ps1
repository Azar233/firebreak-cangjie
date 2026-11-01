param([switch]$Verify, [switch]$VerifyMagic, [switch]$Run, [string]$MinecraftAssets = $env:MINECRAFT_ASSETS)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $sdk = Join-Path $PSScriptRoot '../.tools/cangjie'
    if (!(Test-Path "$sdk/envsetup.ps1")) { $sdk = $env:CANGJIE_HOME }
    if (!$sdk -or !(Test-Path "$sdk/envsetup.ps1")) { throw 'Cangjie SDK 1.0.5 required. Set CANGJIE_HOME.' }
    . "$sdk/envsetup.ps1"
    & './tools/prepare-runtime.ps1'
    $stdx = (Resolve-Path '../.tools/stdx-1.0.5.1/windows_x86_64_cjnative/dynamic/stdx').Path
    $env:Path = $stdx + ';' + $env:Path
    $manifest = Get-Content -LiteralPath 'assets/manifest.json' -Raw -Encoding utf8 | ConvertFrom-Json
    if (!$MinecraftAssets) { $MinecraftAssets = Join-Path "$PSScriptRoot/assets" $manifest.source }
    if (!(Test-Path -LiteralPath $MinecraftAssets)) { throw 'Set MINECRAFT_ASSETS or pass -MinecraftAssets pointing to the original resource root (contains textures/ and font/).' }
    $source = (Resolve-Path -LiteralPath $MinecraftAssets).Path
    $files = @($manifest.files)
    $files += @($manifest.blocks | ForEach-Object { "textures/block/$_.png" })
    $files += @($manifest.items | ForEach-Object { "textures/item/$_.png" })
    $sourceText = (Get-ChildItem -LiteralPath 'src' -Filter '*.cj' | Get-Content -Raw -Encoding utf8) -join "`n"
    $pages = @($sourceText.ToCharArray() | Where-Object { [int]$_ -ge 127 -and [int]$_ -le 65535 } | ForEach-Object { '{0:x2}' -f ([int]$_ -shr 8) } | Sort-Object -Unique)
    $files += @($pages | ForEach-Object { "textures/font/unicode_page_$_.png" })
    foreach ($relative in $files) {
        $assetPath = Join-Path $source $relative
        if (!(Test-Path -LiteralPath $assetPath)) { throw "Missing original Minecraft resource: $assetPath" }
        $destination = Join-Path "$PSScriptRoot/assets/minecraft" $relative
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $assetPath -Destination $destination -Force
    }
    New-Item -ItemType Directory -Path artifacts -Force | Out-Null
    @{
        files = $files; count = $files.Count; unicodePages = $pages
        source = $source; date = '2026-11-01'
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath 'artifacts/resource-copy.json' -Encoding utf8
    & "$sdk/tools/bin/cjpm.exe" build
    if ($LASTEXITCODE -ne 0) { throw 'Firebreak build failed.' }
    Get-ChildItem -LiteralPath 'vendor/SDL/.sdl3' -Filter '*.dll' | Copy-Item -Destination 'target/release/bin' -Force
    if ($Verify) {
        $previousErrorAction = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & './target/release/bin/main.exe' --verify 2>&1 | Tee-Object -FilePath 'artifacts/p3-checks.log'
            $checkExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previousErrorAction }
        if ($checkExit -ne 0) { throw "Workbench checks failed ($checkExit). See artifacts/p3-checks.log." }
    }
    if ($VerifyMagic) { & './tools/verify-magic.ps1' }
    if ($Run) { & './target/release/bin/main.exe' }
} finally { Pop-Location }
