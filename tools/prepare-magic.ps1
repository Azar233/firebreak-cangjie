# Development-only dependency preparation; not required to run the P0 workbench.
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$workspace = Split-Path $project -Parent
$magic = Join-Path $workspace '.reference/CangjieMagic'
$pinnedCommit = 'bc4624fac86ad8498b61d7e5f3b1168659bc72b5'
if (!(Test-Path "$magic/cjpm.toml")) {
    git clone --no-checkout https://github.com/cangjiepl/CangjieMagic.git $magic
    if ($LASTEXITCODE -ne 0) { throw 'CangjieMagic clone failed.' }
    git -C $magic checkout --detach $pinnedCommit
    if ($LASTEXITCODE -ne 0) { throw 'CangjieMagic pinned checkout failed.' }
}
$actual = (git -C $magic rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actual -ne $pinnedCommit) {
    throw "Existing CangjieMagic is not the tested commit; preserve it and inspect before proceeding: $actual"
}
$stdx = Join-Path $workspace '.tools/stdx-1.0.5.1'
if (!(Test-Path "$stdx/windows_x86_64_cjnative/dynamic/stdx/libstdx.encoding.json.dll")) {
    $archive = Join-Path $workspace '.tools/stdx-1.0.5.1.zip'
    if (!(Test-Path $archive)) {
        Invoke-WebRequest -Uri 'https://gitcode.com/Cangjie/cangjie_stdx/releases/download/v1.0.5.1/cangjie-stdx-windows-x64-1.0.5.1.zip' -OutFile $archive -UseBasicParsing
    }
    $expectedHash = '8CD08133C4F1152ACDCFF00C923D9ABE8184F081D6B92E924D2285F7E27F7162'
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) { throw 'stdx archive differs from the tested download.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $stdx -Force
}
$file = Join-Path $magic 'cjpm.toml'
$text = [IO.File]::ReadAllText($file)
$old = './libs/cangjie-stdx-windows-x64-1.0.0.1/windows_x86_64_llvm/dynamic/stdx'
$new = '../../.tools/stdx-1.0.5.1/windows_x86_64_cjnative/dynamic/stdx'
if (!$text.Contains($old) -and !$text.Contains($new)) { throw 'Unexpected CangjieMagic stdx configuration; inspect manually.' }
if ($text.Contains($old)) { [IO.File]::WriteAllText($file, $text.Replace($old,$new), [Text.UTF8Encoding]::new($false)) }
# Public factories for the pinned framework's protected streaming constructors.
# Keep its transport unused: Firebreak retains native Windows TLS validation.
$interop = @'
package magic.core.model
import magic.core.message.Message
public func firebreakChunk(text: String, done!: Bool = false): AsyncChatChunk {
    AsyncChatChunk(message: Message.assistant(text), done: done)
}
public func firebreakStream(model: String, chunks: Iterator<AsyncChatChunk>): AsyncChatResponse {
    AsyncChatResponse(model, chunks)
}
'@
$interopPath = Join-Path $magic 'src/core/model/firebreak_interop.cj'
if (!(Test-Path -LiteralPath $interopPath) -or [IO.File]::ReadAllText($interopPath) -ne $interop) {
    [IO.File]::WriteAllText($interopPath, $interop, [Text.UTF8Encoding]::new($false))
}
Write-Output "Prepared CangjieMagic $pinnedCommit with stdx 1.0.5.1 and streaming constructor factories."
