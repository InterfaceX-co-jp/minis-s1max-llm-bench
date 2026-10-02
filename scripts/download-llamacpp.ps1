#Requires -Version 5.1
<#
.SYNOPSIS
  Fetch a Windows llama.cpp build (qwen4exp-capable) into .\bin\.
.DESCRIPTION
  Qwen3.8-Flash-Next needs a llama.cpp build with the qwen4exp / MTP graph
  (PR #27742 class). Official releases may lag; this downloads the official
  release by default and lets you point at any other zip URL.
.EXAMPLE
  .\download-llamacpp.ps1
  .\download-llamacpp.ps1 -ZipUrl https://github.com/USER/llama.cpp-fork/releases/download/v1/foo-win-x64.zip
#>
param(
    [string]$ZipUrl = '',
    [string]$OutDir = "$PSScriptRoot\..\bin"
)
$ErrorActionPreference = 'Stop'

if (-not $ZipUrl) {
    # Resolve the latest official release zip for Windows x64
    $api = 'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest'
    $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'bench' }
    $asset = $rel.assets | Where-Object { $_.name -match 'win.*x64.*zip|llama-.*bin.*win-x64' } | Select-Object -First 1
    if (-not $asset) { throw "No Windows zip asset found in latest release. Pass -ZipUrl manually (qwen4exp-capable build required)." }
    $ZipUrl = $asset.browser_download_url
    Write-Host "Latest release asset: $($asset.name)"
}

$zip = Join-Path $env:TEMP ('llamacpp-' + [guid]::NewGuid() + '.zip')
Write-Host "Downloading $ZipUrl"
& curl.exe -L --fail --retry 5 --retry-delay 3 -o $zip $ZipUrl
if ($LASTEXITCODE -ne 0) { throw "Download failed" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Expand-Archive -Path $zip -DestinationPath $OutDir -Force
Remove-Item $zip

$cli = Get-ChildItem -Path $OutDir -Recurse -Filter 'llama-cli.exe' | Select-Object -First 1
if (-not $cli) { throw 'llama-cli.exe not found after extract.' }
Write-Host "OK: $($cli.FullName)" -ForegroundColor Green
Write-Host 'NOTE: Qwen3.8-Flash-Next requires a qwen4exp-capable build (MTP / graph_mtp).'
Write-Host '      If official build lacks it, pass -ZipUrl of a fork build.'
