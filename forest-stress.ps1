param([switch]$Benchmark, [switch]$Gpu, [string]$Example = 'examples/large-forest.json')
$ErrorActionPreference = 'Stop'
$previousHeap = $env:cjHeapSize
Push-Location $PSScriptRoot
try {
    if (!(Test-Path 'target/release/bin/main.exe')) { & './build.ps1' }
    $sdk = Join-Path $PSScriptRoot '../.tools/cangjie'
    if (!(Test-Path "$sdk/envsetup.ps1")) { $sdk = $env:CANGJIE_HOME }
    . "$sdk/envsetup.ps1"
    $env:Path = (Resolve-Path '../.tools/stdx-1.0.5.1/windows_x86_64_cjnative/dynamic/stdx').Path + ';' + $env:Path
    # Large dense diagnostic arrays exceed the runtime's default 256 MB heap.
    # Scoped to this launcher; the regular workbench retains its own defaults.
    $env:cjHeapSize = '2GB'
    if ($Benchmark) {
        @{
            cpu = @(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfLogicalProcessors)
            ramGiB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
            gpu = @(Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name)
        } | ConvertTo-Json -Depth 4 | Set-Content 'artifacts/forest-hardware.json' -Encoding utf8
        & './target/release/bin/main.exe' $(if($Gpu){'--benchmark-gpu'}else{'--benchmark-forest'})
    } else { & './target/release/bin/main.exe' --forest-stress $Example }
    if ($LASTEXITCODE -ne 0) { throw 'Forest diagnostic exited with an error.' }
} finally { $env:cjHeapSize = $previousHeap; Pop-Location }
