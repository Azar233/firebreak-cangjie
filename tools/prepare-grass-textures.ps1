$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Pin the modern vanilla texture family; never replace the user's source pack.
$sha1 = '30c73b1c5da787909b2f73340419fdf13b9def88'
$cache = Join-Path $PSScriptRoot '../.reference/minecraft-1.21.1-client.jar'
$destination = Join-Path $PSScriptRoot '../assets/minecraft/textures/block'
$textures = @('grass_block_top','grass_block_side','grass_block_side_overlay','dirt')
New-Item -ItemType Directory -Force -Path (Split-Path $cache -Parent),$destination | Out-Null
if (!(Test-Path -LiteralPath $cache) -or (Get-FileHash -LiteralPath $cache -Algorithm SHA1).Hash.ToLowerInvariant() -ne $sha1) {
    Invoke-WebRequest -UseBasicParsing -Uri "https://piston-data.mojang.com/v1/objects/$sha1/client.jar" -OutFile $cache
}
if ((Get-FileHash -LiteralPath $cache -Algorithm SHA1).Hash.ToLowerInvariant() -ne $sha1) { throw 'Minecraft grass texture source checksum mismatch.' }
$archive = [IO.Compression.ZipFile]::OpenRead($cache)
try {
    foreach ($texture in $textures) {
        $entry = $archive.GetEntry("assets/minecraft/textures/block/$texture.png")
        if (!$entry) { throw "Missing modern vanilla texture: $texture" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $destination "$texture.png"),$true)
    }
} finally { $archive.Dispose() }
Write-Host 'Minecraft 1.21.1 grass texture family verified and prepared.'
