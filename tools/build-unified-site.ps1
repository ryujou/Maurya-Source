param(
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$homeSource = Join-Path $workspace "src\server\xtbang-home"
$mauryaSource = Join-Path $workspace "src\server\maurya-download"
$previewRoot = Join-Path $workspace "local-preview"

if (-not $SkipBuild) {
  Push-Location $homeSource
  try {
    npm run build
  } finally {
    Pop-Location
  }
}

New-Item -ItemType Directory -Path $previewRoot -Force | Out-Null
Get-ChildItem (Join-Path $homeSource "dist") -Force | Copy-Item -Destination $previewRoot -Recurse -Force

$previewMaurya = Join-Path $previewRoot "maurya"
if (Test-Path $previewMaurya) {
  Remove-Item -LiteralPath $previewMaurya -Recurse -Force
}
Copy-Item -LiteralPath $mauryaSource -Destination $previewMaurya -Recurse -Force

Write-Output "Unified local site built under $previewRoot"
Write-Output "Root source: $homeSource"
Write-Output "Maurya source: $mauryaSource"
