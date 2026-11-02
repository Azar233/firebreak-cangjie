# Reproducible development/runtime dependencies; binaries stay outside Git.
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$cache = [IO.Path]::GetFullPath((Join-Path $project '../.tools'))
New-Item -ItemType Directory -Path $cache -Force | Out-Null
function Get-PinnedArchive($url,$destination,$sha) {
    if (!(Test-Path -LiteralPath $destination)) { Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing }
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $sha) {
        throw "Dependency checksum mismatch; inspect the cached archive: $destination"
    }
}
$stdx = Join-Path $cache 'stdx-1.0.5.1'
if (!(Test-Path -LiteralPath "$stdx/windows_x86_64_cjnative/dynamic/stdx/libstdx.encoding.json.dll")) {
    $archive = Join-Path $cache 'stdx-1.0.5.1.zip'
    Get-PinnedArchive 'https://gitcode.com/Cangjie/cangjie_stdx/releases/download/v1.0.5.1/cangjie-stdx-windows-x64-1.0.5.1.zip' $archive '8CD08133C4F1152ACDCFF00C923D9ABE8184F081D6B92E924D2285F7E27F7162'
    Expand-Archive -LiteralPath $archive -DestinationPath $stdx -Force
}
$native = Join-Path $project 'vendor/SDL/.sdl3'
New-Item -ItemType Directory -Path $native -Force | Out-Null
$releases = @(
    @('SDL','3.4.12','SDL3','326E9F5AE2CBAB478C03A9E2B22A560E5A9358B5F5EED8E61F5A7C8333750CF1'),
    @('SDL_image','3.4.6','SDL3_image','B851A5203B3ECF928541EEF6B563F7DB39EC1B1732F130D9AFC11050AC76C7A6'),
    @('SDL_ttf','3.2.2','SDL3_ttf','13455007029CF487C5AACAA6FF84406BE78FFDBED08F933ABA3668680FF245F8'),
    @('SDL_mixer','3.2.4','SDL3_mixer','9AF526F8DEFC72CA3B979A6DC4D9E549E5BE4DD8DB3190CFA8941923A78F73CB')
)
foreach ($release in $releases) {
    $repo,$version,$library,$sha = $release
    if (!(Test-Path -LiteralPath "$native/$library.dll") -or ($repo -eq 'SDL_mixer' -and !(Test-Path -LiteralPath "$native/SDL3_mixer-LICENSE.txt"))) {
        $filename = "$library-$version-win32-x64.zip"
        $archive = Join-Path $cache $filename
        Get-PinnedArchive "https://github.com/libsdl-org/$repo/releases/download/release-$version/$filename" $archive $sha
        $expanded = Join-Path $cache "firebreak-native/$library-$version"
        Expand-Archive -LiteralPath $archive -DestinationPath $expanded -Force
        if ($repo -eq 'SDL_mixer') {
            # OGG Vorbis support is built in; optional codec DLLs are not used.
            Copy-Item -LiteralPath "$expanded/$library.dll" -Destination $native -Force
            Copy-Item -LiteralPath "$expanded/LICENSE.txt" -Destination "$native/SDL3_mixer-LICENSE.txt" -Force
        } else {
            Get-ChildItem -LiteralPath $expanded -Filter '*.dll' -Recurse | Copy-Item -Destination $native -Force
        }
    }
    if (!(Test-Path -LiteralPath "$native/$library.dll")) { throw "Missing native library: $library" }
    if (!(Test-Path -LiteralPath "$native/lib$library.dll")) { Copy-Item -LiteralPath "$native/$library.dll" -Destination "$native/lib$library.dll" }
}
Write-Output 'Pinned stdx and SDL runtime dependencies are ready.'
