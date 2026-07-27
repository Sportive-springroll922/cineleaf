[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepositoryRoot "Windows\src\Cineleaf.Windows.App\Assets\Cineleaf.ico"
}

$sizes = @(16, 32, 64, 128, 256)
$images = foreach ($size in $sizes) {
    $path = Join-Path $RepositoryRoot "Cineleaf\Assets.xcassets\AppIcon.appiconset\icon-$size.png"
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing icon source: $path" }
    [PSCustomObject]@{ Size = $size; Bytes = [IO.File]::ReadAllBytes($path) }
}

$parent = Split-Path -Parent $OutputPath
[IO.Directory]::CreateDirectory($parent) | Out-Null
$stream = [IO.File]::Open($OutputPath, [IO.FileMode]::Create, [IO.FileAccess]::Write)
$writer = [IO.BinaryWriter]::new($stream)
try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$images.Count)
    $offset = 6 + 16 * $images.Count
    foreach ($image in $images) {
        $writer.Write([Byte]($(if ($image.Size -eq 256) { 0 } else { $image.Size })))
        $writer.Write([Byte]($(if ($image.Size -eq 256) { 0 } else { $image.Size })))
        $writer.Write([Byte]0)
        $writer.Write([Byte]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]$image.Bytes.Length)
        $writer.Write([UInt32]$offset)
        $offset += $image.Bytes.Length
    }
    foreach ($image in $images) { $writer.Write($image.Bytes) }
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

Write-Output $OutputPath
