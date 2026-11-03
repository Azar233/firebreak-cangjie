$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$project = Split-Path $PSScriptRoot -Parent
$destination = Join-Path $project 'assets/minecraft'
$cache = Join-Path $project '.reference'
$manifest = Get-Content -LiteralPath (Join-Path $project 'assets/manifest.json') -Raw -Encoding utf8 | ConvertFrom-Json
$required = @($manifest.files)
$required += @($manifest.blocks | ForEach-Object { "textures/block/$_.png" })
$required += @($manifest.items | ForEach-Object { "textures/item/$_.png" })
New-Item -ItemType Directory -Path $destination,$cache -Force | Out-Null

function Get-VerifiedAsset($url,$path,$hash) {
    if (!(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA1).Hash.ToLowerInvariant() -ne $hash) {
        $temporary = "$path.downloading"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $temporary
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA1).Hash.ToLowerInvariant() -ne $hash) { throw "Minecraft download checksum mismatch: $url" }
        Move-Item -LiteralPath $temporary -Destination $path -Force
    }
}

if ($env:MINECRAFT_ASSETS) {
    $source = (Resolve-Path -LiteralPath $env:MINECRAFT_ASSETS).Path
    $pages = @(Get-ChildItem -LiteralPath (Join-Path $source 'textures/font') -Filter 'unicode_page_*.png')
    $files = @($required) + @($pages | ForEach-Object { "textures/font/$($_.Name)" })
    foreach ($relative in $files) {
        $from = Join-Path $source $relative
        if (!(Test-Path -LiteralPath $from)) { throw "Missing requested Minecraft resource: $from" }
        $to = Join-Path $destination $relative
        New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $from -Destination $to -Force
    }
} else {
    $missing = @($required | Where-Object { !(Test-Path -LiteralPath (Join-Path $destination $_)) })
    $pages = @(Get-ChildItem -LiteralPath (Join-Path $destination 'textures/font') -Filter 'unicode_page_*.png' -ErrorAction SilentlyContinue)
    if ($missing.Count -gt 0 -or $pages.Count -eq 0) {
        # Legacy Unicode/GUI atlases are required by the bitmap renderer; current
        # blocks/items come from the same modern family as the grass textures.
        $oldHash = '0f275bc1547d01fa5f56ba34bdc87d981ee12daf'
        $newHash = '30c73b1c5da787909b2f73340419fdf13b9def88'
        $oldJar = Join-Path $cache 'minecraft-1.12.2-client.jar'
        $newJar = Join-Path $cache 'minecraft-1.21.1-client.jar'
        Get-VerifiedAsset "https://piston-data.mojang.com/v1/objects/$oldHash/client.jar" $oldJar $oldHash
        Get-VerifiedAsset "https://piston-data.mojang.com/v1/objects/$newHash/client.jar" $newJar $newHash
        $old = [IO.Compression.ZipFile]::OpenRead($oldJar)
        $new = [IO.Compression.ZipFile]::OpenRead($newJar)
        try {
            $files = @($required)
            $files += @($old.Entries | Where-Object { $_.FullName -like 'assets/minecraft/textures/font/unicode_page_*.png' } | ForEach-Object { $_.FullName.Substring(17) })
            foreach ($relative in $files) {
                $to = Join-Path $destination $relative
                if (Test-Path -LiteralPath $to) { continue }
                $entry = $new.GetEntry("assets/minecraft/$relative")
                if (!$entry) { $entry = $old.GetEntry("assets/minecraft/$relative") }
                if (!$entry) { throw "Pinned official resources do not contain $relative" }
                New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$to,$false)
            }
        } finally { $old.Dispose();$new.Dispose() }
    }
}

New-Item -ItemType Directory -Path (Join-Path $destination 'sounds') -Force | Out-Null
foreach ($sound in @(
    @('click_stereo.ogg','2fe092579d9637e2d160319820ee08e60a237bb7'),
    @('Minecraft.ogg','50a59a4f56e4046701b758ddbb1c1587efa4cadf')
)) {
    $to = Join-Path $destination "sounds/$($sound[0])"
    # Preserve the user's explicitly supplied audio and volume preferences.
    if (!(Test-Path -LiteralPath $to)) {
        $hash = $sound[1];$prefix = $hash.Substring(0,2)
        Get-VerifiedAsset "https://resources.download.minecraft.net/$prefix/$hash" $to $hash
    }
}
Write-Host 'Minecraft resources ready in assets/minecraft (original third-party rights; not MIT).'
