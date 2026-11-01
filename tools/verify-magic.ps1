$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $project '../.tools/cangjie'
if (!(Test-Path "$sdk/envsetup.ps1")) { $sdk = $env:CANGJIE_HOME }
if (!$sdk -or !(Test-Path "$sdk/envsetup.ps1")) { throw 'Cangjie SDK required.' }
. "$sdk/envsetup.ps1"
$magic = Join-Path $project '../.reference/CangjieMagic'
if (!(Test-Path "$magic/cjpm.toml")) { throw 'Prepare the pinned CangjieMagic source per docs/P0_VALIDATION.md.' }
Push-Location "$PSScriptRoot/magic-probe"
try {
    cjpm build 2>&1 | Tee-Object -FilePath "$project/artifacts/magic-probe-build.log"
    if ($LASTEXITCODE -ne 0) { throw 'CangjieMagic probe build failed.' }
    $runtimeDirs = @(
        Get-ChildItem -LiteralPath './target/release' -Filter '*.dll' -Recurse | Select-Object -ExpandProperty DirectoryName -Unique
        Get-ChildItem -LiteralPath "$magic/target/release" -Filter '*.dll' -Recurse | Select-Object -ExpandProperty DirectoryName -Unique
        Get-ChildItem -LiteralPath "$project/../.tools/stdx-1.0.5.1/windows_x86_64_cjnative/dynamic/stdx" -Filter '*.dll' | Select-Object -ExpandProperty DirectoryName -Unique
    )
    $env:Path = ($runtimeDirs -join ';') + ';' + $env:Path
    & './target/release/bin/firebreak_probe.exe' 2>&1 | Tee-Object -FilePath "$project/artifacts/magic-probe-run.log"
    if ($LASTEXITCODE -ne 0) { throw "CangjieMagic offline probe failed ($LASTEXITCODE)." }
} finally { Pop-Location }
