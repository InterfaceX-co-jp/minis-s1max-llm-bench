#Requires -Version 5.1
<#
.SYNOPSIS
  Fetch the official llama.cpp Windows x64 Vulkan build into .\bin\.
.DESCRIPTION
  Downloads the "Windows x64 (Vulkan)" zip asset from the latest ggml-org/llama.cpp
  release. Vulkan is the easiest path on Minisforum MS-S1 MAX (Radeon 8060S / Strix Halo)
  — no ROCm/HIP runtime needed. Works with PowerShell 5.1+.
.EXAMPLE
  .\download-llamacpp.ps1
  .\download-llamacpp.ps1 -ZipUrl https://github.com/.../llama-bXXXX-bin-win-vulkan-x64.zip
#>
param(
    # Asset name pattern: match the Vulkan x64 zip
    [string]$AssetPattern = 'win.*vulkan.*x64\.zip|llama-.*bin-win-vulkan-x64',
    [string]$ZipUrl = '',
    [string]$OutDir = "$PSScriptRoot\..\bin"
)
$ErrorActionPreference = 'Stop'

if (-not $ZipUrl) {
    $api = 'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest'
    $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'minis-bench' }
    $asset = $rel.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
    if (-not $asset) {
        Write-Host "Available assets:" -ForegroundColor Yellow
        $rel.assets | ForEach-Object { Write-Host "  $($_.name)" }
        throw "No Vulkan x64 zip matched pattern '$AssetPattern' in latest release. Pass -ZipUrl manually."
    }
    $ZipUrl = $asset.browser_download_url
    Write-Host "Latest release asset: $($asset.name)"
}

$zip = Join-Path $env:TEMP ('llamacpp-' + [guid]::NewGuid() + '.zip')
Write-Host "Downloading $ZipUrl"
& curl.exe -L --fail --retry 5 --retry-delay 3 -o $zip $ZipUrl
if ($LASTEXITCODE -ne 0) { throw "Download failed: $ZipUrl" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Expand-Archive -Path $zip -DestinationPath $OutDir -Force
Remove-Item $zip

$cli = Get-ChildItem -Path $OutDir -Recurse -Filter 'llama-cli.exe' | Select-Object -First 1
if (-not $cli) { throw 'llama-cli.exe not found after extract.' }
$bindir = $cli.DirectoryName
Write-Host "OK: $bindir" -ForegroundColor Green

# Copy exe paths to the repo root convention used by run-bench scripts
foreach ($tool in 'llama-cli.exe','llama-bench.exe','llama-server.exe','gguf-split.exe','llama-quantize.exe') {
    $t = Join-Path $bindir $tool
    if (Test-Path $t) { Write-Host "  found: $t" }
}

Write-Host "`nVerify GPU is visible:" -ForegroundColor Cyan
Write-Host "  $bindir\llama-cli.exe --list-devices"
