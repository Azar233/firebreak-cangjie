param([string[]]$AppArguments = @())
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    if (!(Test-Path 'target/release/bin/main.exe')) { & './build.ps1' }
    $sdk = Join-Path $PSScriptRoot '../.tools/cangjie'
    if (!(Test-Path "$sdk/envsetup.ps1")) { $sdk = $env:CANGJIE_HOME }
    if (!$sdk -or !(Test-Path "$sdk/envsetup.ps1")) { throw 'Cangjie SDK required.' }
    . "$sdk/envsetup.ps1"
    $env:Path = (Resolve-Path '../.tools/stdx-1.0.5.1/windows_x86_64_cjnative/dynamic/stdx').Path + ';' + $env:Path
    & './target/release/bin/main.exe' @AppArguments
    if ($LASTEXITCODE -ne 0) { throw 'Firebreak app exited with an error.' }
} finally { Pop-Location }
