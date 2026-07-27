[CmdletBinding()]
param(
    [string]$OutputDirectory = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot "build\ffmpeg-windows"
}

$archiveUrl = "https://github.com/luucabg/cineleaf/releases/download/windows-toolchain-8.1.2-20260726/ffmpeg-n8.1-latest-win64-lgpl-8.1.zip"
$expectedSha256 = "f51f95215aa3b0bccc9c2faac292d57407257acc74e989c4d9c66ca2d02bd3f1"
$archive = Join-Path $repositoryRoot "build\ffmpeg-n8.1-latest-win64-lgpl-8.1.zip"
$extract = Join-Path $repositoryRoot "build\ffmpeg-windows-extracted"

if ($Force -or -not (Test-Path -LiteralPath $archive)) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $archive)) | Out-Null
    Invoke-WebRequest -Uri $archiveUrl -OutFile $archive
}
$actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expectedSha256) {
    throw "FFmpeg checksum mismatch. Expected $expectedSha256 but received $actual. Refusing to package unverified tools."
}

if ($Force -and (Test-Path -LiteralPath $extract)) {
    $resolvedExtract = [IO.Path]::GetFullPath($extract)
    $resolvedBuild = [IO.Path]::GetFullPath((Join-Path $repositoryRoot "build"))
    if (-not $resolvedExtract.StartsWith($resolvedBuild, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to clear a path outside build." }
    Remove-Item -LiteralPath $resolvedExtract -Recurse -Force
}
if (-not (Test-Path -LiteralPath $extract)) { Expand-Archive -LiteralPath $archive -DestinationPath $extract }
$packageRoot = Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
if ($null -eq $packageRoot) { throw "The FFmpeg archive is empty." }

[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
Copy-Item -LiteralPath (Join-Path $packageRoot.FullName "bin\ffmpeg.exe") -Destination $OutputDirectory -Force
Copy-Item -LiteralPath (Join-Path $packageRoot.FullName "bin\ffprobe.exe") -Destination $OutputDirectory -Force
Copy-Item -LiteralPath (Join-Path $packageRoot.FullName "LICENSE.txt") -Destination (Join-Path $OutputDirectory "FFmpeg-LICENSE.txt") -Force

$version = & (Join-Path $OutputDirectory "ffmpeg.exe") -hide_banner -version 2>&1
if ($LASTEXITCODE -ne 0 -or $version -match "--enable-gpl") { throw "The acquired FFmpeg build failed the LGPL configuration check." }
Write-Output $OutputDirectory
