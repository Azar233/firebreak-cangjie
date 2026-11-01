param(
    [ValidateSet('Status','Refresh','Query','Callers','Callees','Impact','Affected')]
    [string]$Action = 'Status',
    [string[]]$Names = @(),
    [ValidateSet('Project','SDL','Magic')]
    [string]$Scope = 'Project',
    [ValidateRange(1,8)]
    [int]$Depth = 4,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolRoot = [IO.Path]::GetFullPath((Join-Path $project '../.tools/codegraph'))
$shim = Join-Path $toolRoot 'node_modules/@cangjie-lang/codegraph/npm-shim.js'
$metadata = Join-Path $toolRoot 'node_modules/@cangjie-lang/codegraph/package.json'
if (!(Test-Path -LiteralPath $metadata) -or !(Test-Path -LiteralPath $shim)) {
    throw 'Run tools/prepare-codegraph.ps1 first. CodeGraph is optional and is not installed automatically.'
}
if ((Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json).version -ne '1.5.0-cangjie-1.0.5.3') {
    throw 'Unexpected CodeGraph version. Run tools/prepare-codegraph.ps1 to restore the pinned version.'
}
$node = (Get-Command node.exe -ErrorAction Stop).Source
$root = switch ($Scope) {
    'Project' { $project }
    'SDL' { Join-Path $project 'vendor/SDL' }
    'Magic' { [IO.Path]::GetFullPath((Join-Path $project '../.reference/CangjieMagic')) }
}
if (!(Test-Path -LiteralPath (Join-Path $root 'src'))) { throw "Source scope is unavailable: $root" }
if ($Action -in @('Query','Callers','Callees','Impact') -and ($Names.Count -ne 1 -or [string]::IsNullOrWhiteSpace($Names[0]))) {
    throw 'Supply one search term or qualified symbol using -Names, for example FireRun.advance.'
}
if ($Action -eq 'Affected' -and ($Scope -ne 'Project' -or $Names.Count -eq 0)) {
    throw 'Affected is for explicit project source paths only, for example -Names src/scene.cj.'
}
if ($Json -and $Action -in @('Status','Refresh')) { throw 'Status uses text output; omit -Json.' }
foreach ($name in $Names) {
    if ($name.StartsWith('-')) { throw 'Search terms and source paths cannot start with a CLI option prefix.' }
}
if ($Action -eq 'Affected') {
    foreach ($name in $Names) {
        $resolved = [IO.Path]::GetFullPath((Join-Path $root $name))
        if (![string]::Equals($resolved,$root,[StringComparison]::OrdinalIgnoreCase) -and
            !$resolved.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Affected source paths must stay inside the project.'
        }
    }
}

# Process-only settings are restored even after a failed query. No install/MCP
# command is exposed, and no daemon is needed for these on-demand queries.
$settings = @{
    CODEGRAPH_TELEMETRY='0'; DO_NOT_TRACK='1'; CODEGRAPH_NO_UPDATE_CHECK='1'
    CODEGRAPH_NO_DOWNLOAD='1'; CODEGRAPH_NO_DAEMON='1'
}
$previous = @{}
foreach ($key in $settings.Keys) {
    $previous[$key] = [Environment]::GetEnvironmentVariable($key,'Process')
    [Environment]::SetEnvironmentVariable($key,$settings[$key],'Process')
}
function Invoke-Graph([string[]]$GraphArgs) {
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $result = (& $node $shim @GraphArgs 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPreference }
    if ($code -ne 0) { throw "CodeGraph failed ($code): $result" }
    return $result.Trim()
}
try {
    # Always reconcile current sources before querying: this is a live index,
    # not the frozen copies used in the earlier assessment.
    $database = Join-Path $root '.codegraph/codegraph.db'
    $syncAction = if (Test-Path -LiteralPath $database) { 'sync' } else { 'init' }
    $syncOutput = Invoke-Graph -GraphArgs @($syncAction,$root)
    Write-Verbose $syncOutput
    # Upstream leaves its generated ignore file trackable. Keep this optional
    # cache fully local even when a dependency is its own nested Git repository.
    $cacheIgnore = Join-Path $root '.codegraph/.gitignore'
    if (Test-Path -LiteralPath $cacheIgnore) {
        $ignoreText = Get-Content -LiteralPath $cacheIgnore -Raw
        if ($ignoreText.StartsWith('# CodeGraph data files') -and $ignoreText -match '(?m)^!\.gitignore\s*$') {
            $ignoreText = $ignoreText -replace '(?m)^!\.gitignore\s*$', '# This generated ignore file is local too.'
            Set-Content -LiteralPath $cacheIgnore -Value $ignoreText -Encoding utf8
        }
    }
    $cgArgs = switch ($Action) {
        'Status' { @('status',$root) }
        'Refresh' { @('status',$root) }
        'Query' { @('query',$Names[0],'--path',$root) }
        'Callers' { @('callers',$Names[0],'--path',$root,'--limit','200') }
        'Callees' { @('callees',$Names[0],'--path',$root,'--limit','200') }
        'Impact' { @('impact',$Names[0],'--path',$root,'--depth',"$Depth") }
        'Affected' { @('affected') + $Names + @('--path',$root,'--depth',"$Depth",'--filter','src/verify*.cj') }
    }
    if ($Json) {
        $cgArgs += '--json'
    }
    Invoke-Graph -GraphArgs $cgArgs
} finally {
    foreach ($key in $settings.Keys) {
        if ($null -eq $previous[$key]) { Remove-Item -LiteralPath "Env:$key" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($key,$previous[$key],'Process') }
    }
}
