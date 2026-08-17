param(
  [string]$BaseUrl = "http://127.0.0.1:8765"
)

$ErrorActionPreference = "Stop"
$paths = @("/", "/maurya/", "/maurya/download/", "/maurya/flash/", "/maurya/script/", "/prototypes/unified-home/")

foreach ($path in $paths) {
  $response = Invoke-WebRequest -Uri ($BaseUrl + $path) -UseBasicParsing -TimeoutSec 20
  if ($response.StatusCode -ne 200) {
    throw "$path returned HTTP $($response.StatusCode)"
  }
  Write-Output "$path`t$($response.StatusCode)`t$($response.Content.Length) bytes"
}

$workspace = Split-Path -Parent $PSScriptRoot
$cssFiles = @(
  (Join-Path $workspace "src\server\xtbang-home\src\web\styles.css"),
  (Join-Path $workspace "src\server\maurya-download\assets\site.css")
)
$forbidden = @("transition: all", "scale(0)")
foreach ($file in $cssFiles) {
  $content = Get-Content $file -Raw
  foreach ($token in $forbidden) {
    if ($content.Contains($token)) {
      throw "$token remains in $file"
    }
  }
}

$scriptPage = Get-Content (Join-Path $workspace "src\server\maurya-download\script\index.html") -Raw
foreach ($token in @("70颗", "70个", "量子星云", "超新星")) {
  if ($scriptPage.Contains($token)) {
    throw "$token remains in the Script manual"
  }
}

$manifestFiles = Get-ChildItem (Join-Path $workspace "src\server\maurya-download\ota\stable") -Filter "manifest.json" -Recurse
foreach ($manifest in $manifestFiles) {
  $manifestContent = Get-Content $manifest.FullName -Raw
  foreach ($token in @("70颗", "70个")) {
    if ($manifestContent.Contains($token)) {
      throw "$token remains in $($manifest.FullName)"
    }
  }
}

$communityData = Get-Content (Join-Path $workspace "src\server\xtbang-home\data\community.json") -Raw
if ($communityData.Contains("i.imgs.ovh")) {
  throw "Community photos must use local assets for deterministic previews"
}
if (-not (Test-Path (Join-Path $workspace "src\server\xtbang-home\public\community-photo.jpg"))) {
  throw "Local community photo asset is missing"
}

Write-Output "Unified site checks passed."
