param()
$ErrorActionPreference = 'Stop'
$version = '1.5.0-cangjie-1.0.5.3'
$toolRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../.tools/codegraph'))
$metadata = Join-Path $toolRoot 'node_modules/@cangjie-lang/codegraph/package.json'
$bundle = Join-Path $toolRoot 'node_modules/@cangjie-lang/codegraph-win32-x64/node.exe'
if ((Test-Path -LiteralPath $metadata) -and (Test-Path -LiteralPath $bundle)) {
    if ((Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json).version -eq $version) {
        Write-Output "CodeGraph $version is ready in $toolRoot"
        return
    }
}
if (![Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
    throw 'This project helper currently supports Windows x64.'
}
$npm = (Get-Command npm.cmd -ErrorAction Stop).Source
New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
& $npm install --prefix $toolRoot --no-save --package-lock=false --ignore-scripts --no-audit --no-fund "@cangjie-lang/codegraph@$version"
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $bundle)) { throw 'CodeGraph local setup failed.' }
if ((Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json).version -ne $version) { throw 'Unexpected CodeGraph version.' }
Write-Output "CodeGraph $version installed locally; no agent configuration was changed."
