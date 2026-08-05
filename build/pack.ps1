<#
.SYNOPSIS
  Buduje zalaczniki wydania presetu i (opcjonalnie) wystawia je na GitHubie.

.DESCRIPTION
  Kolejnosc jest celowa: NAJPIERW walidacja, potem cokolwiek innego. Uszkodzony
  preset nie ma prawa opuscic repozytorium - u odbiorcy objawi sie jako "preset
  uszkodzony" i zablokuje mu caly Patcher.

  Powstaje katalog dist/ z zalacznikami wydania:
    preset-<wersja>.json          <- manifest, Patcher pobiera go zawsze
    ram-keeper-<wersja>.zip       <- narzedzie, pobierane leniwie
    <shaderpack>.zip, .zip.txt    <- shaderpack, pobierany leniwie

.EXAMPLE
  pwsh -File build/pack.ps1                  # samo zbudowanie dist/
.EXAMPLE
  pwsh -File build/pack.ps1 -Release         # + gh release create
#>

[CmdletBinding()]
param(
  [switch] $Release,
  [string] $Tag,
  [string] $Notes
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

try {
  $manifestPath = Join-Path $root 'preset.json'
  $preset = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  $version = $preset.version
  if (-not $Tag) { $Tag = "preset-$version" }

  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw 'Brak node - bez walidacji nie wydajemy. Zainstaluj Node.js albo uruchom validate.js recznie.'
  }

  # ------------------------------------------------------------------ zalaczniki
  Write-Host "== Skladanie zalacznikow (wersja $version)"
  $dist = Join-Path $root 'dist'
  if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
  New-Item -ItemType Directory -Path $dist | Out-Null

  Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $dist "preset-$version.json")
  Write-Host "   preset-$version.json"

  # Narzedzia: kazdy katalog w tools/ leci jako osobne archiwum <nazwa>-<wersja>.zip,
  # bo manifest siega po nie maska (np. "ram-keeper-*.zip").
  $toolsDir = Join-Path $root 'tools'
  if (Test-Path $toolsDir) {
    foreach ($tool in Get-ChildItem -Directory -LiteralPath $toolsDir) {
      $zip = Join-Path $dist ("{0}-{1}.zip" -f $tool.Name, $version)
      Compress-Archive -Path (Join-Path $tool.FullName '*') -DestinationPath $zip -Force
      Write-Host ("   {0}  ({1} KB)" -f (Split-Path -Leaf $zip), [math]::Round((Get-Item $zip).Length / 1KB))
    }
  }

  # Zasoby (shaderpack) ida jak leza - sa juz spakowane i wersjonowane wlasna nazwa.
  $assetsDir = Join-Path $root 'assets'
  if (Test-Path $assetsDir) {
    foreach ($file in Get-ChildItem -File -Recurse -LiteralPath $assetsDir | Where-Object { $_.Name -ne 'README.md' }) {
      Copy-Item -LiteralPath $file.FullName -Destination $dist
      Write-Host ("   {0}  ({1} KB)" -f $file.Name, [math]::Round($file.Length / 1KB))
    }
  }

  # ------------------------------------------------------------------ walidacja
  # Sprawdzamy TO, CO FAKTYCZNIE POJDZIE DO WYDANIA - razem z zipami narzedzi,
  # ktore powstaly przed chwila. Uszkodzony preset nie ma prawa opuscic repozytorium:
  # u odbiorcy objawi sie jako "preset uszkodzony" i zablokuje mu caly Patcher.
  Write-Host "`n== Walidacja manifestu wzgledem dist/"
  & node (Join-Path $PSScriptRoot 'validate.js') $manifestPath --assets $dist
  if ($LASTEXITCODE -ne 0) { throw 'Manifest nie przeszedl walidacji - NIE wydaje.' }

  # ------------------------------------------------------------------ wydanie
  if (-not $Release) {
    Write-Host "`nGotowe: $dist"
    Write-Host "Wydanie: pwsh -File build/pack.ps1 -Release"
    return
  }

  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'Brak gh (GitHub CLI). Zainstaluj: winget install GitHub.cli'
  }
  if (-not $Notes) { $Notes = "Preset $version" }

  Write-Host "`n== Wydanie $Tag"
  $files = Get-ChildItem -File -LiteralPath $dist | ForEach-Object { $_.FullName }

  & gh release view $Tag *> $null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "   wydanie istnieje - dogrywam zalaczniki (--clobber)"
    & gh release upload $Tag @files --clobber
  } else {
    & gh release create $Tag @files --title "Preset $version" --notes $Notes
  }
  if ($LASTEXITCODE -ne 0) { throw 'gh zwrocil blad.' }

  Write-Host "`nWydane. Patcher zobaczy to przy najblizszym 'Sprawdz zrodla'."
} finally {
  Pop-Location
}
