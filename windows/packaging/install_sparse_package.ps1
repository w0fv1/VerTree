param(
  [string]$ExternalLocation = "",
  [string]$IdentityPackagePath = "",
  [switch]$AllowUnsigned,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Resolve-ExistingPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
    return ""
  }
  return (Resolve-Path $Path).Path
}

function Get-StagedSparseRoot {
  if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Write-Error "LOCALAPPDATA is not available."
  }

  return Join-Path $env:LOCALAPPDATA "Vertree\\win11_packaging\\sparse"
}

function Update-StagedSparsePackage {
  $sourceSparseRoot = Join-Path $PSScriptRoot "sparse"
  if (-not (Test-Path $sourceSparseRoot)) {
    Write-Error "Sparse package directory not found: $sourceSparseRoot"
  }

  $stagedSparseRoot = Get-StagedSparseRoot
  if (Test-Path $stagedSparseRoot) {
    Remove-Item $stagedSparseRoot -Recurse -Force
  }

  New-Item -ItemType Directory -Force -Path $stagedSparseRoot | Out-Null
  Copy-Item (Join-Path $sourceSparseRoot "*") $stagedSparseRoot -Recurse -Force

  $stagedManifest = Join-Path $stagedSparseRoot "AppxManifest.xml"
  if (-not (Test-Path $stagedManifest)) {
    Write-Error "Staged AppxManifest not found: $stagedManifest"
  }

  return $stagedManifest
}

function Resolve-IdentityPackagePath {
  if (-not [string]::IsNullOrWhiteSpace($IdentityPackagePath)) {
    if (-not (Test-Path $IdentityPackagePath)) {
      Write-Error "Identity package not found: $IdentityPackagePath"
    }
    return (Resolve-Path $IdentityPackagePath).Path
  }

  $preferred = Join-Path $PSScriptRoot "VertreeSparse.msix"
  if (Test-Path $preferred) {
    return (Resolve-Path $preferred).Path
  }

  $packages = Get-ChildItem -Path $PSScriptRoot -Filter "*.msix" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
  if ($packages) {
    return $packages[0].FullName
  }

  return ""
}

function Get-PackageExternalLocation($Package) {
  if ($null -eq $Package) {
    return ""
  }

  foreach ($name in @("ExternalLocation", "InstallLocation")) {
    $property = $Package.PSObject.Properties[$name]
    if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
      return [string]$property.Value
    }
  }

  return ""
}

if ([string]::IsNullOrWhiteSpace($ExternalLocation)) {
  $ExternalLocation = (Resolve-Path (Join-Path $PSScriptRoot "..\\..\\build\\windows\\x64\\runner\\Debug")).Path
}

if (-not (Test-Path $ExternalLocation)) {
  Write-Error "ExternalLocation not found: $ExternalLocation"
}
$ExternalLocation = (Resolve-Path $ExternalLocation).Path

$packageName = "w0fv1.vertree"
$existing = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue
if ($existing) {
  $currentLocation = Get-PackageExternalLocation $existing
  $resolvedCurrent = Resolve-ExistingPath $currentLocation
  $resolvedTarget = Resolve-ExistingPath $ExternalLocation
  if ($Force -or ($resolvedCurrent -ne $resolvedTarget)) {
    Write-Host "Remove existing sparse package: $($existing.PackageFullName)"
    Remove-AppxPackage -Package $existing.PackageFullName -ErrorAction Stop
  }
}

$allowUnsignedRequested = $AllowUnsigned -or $env:VERTREE_ALLOW_UNSIGNED_MSIX -eq "1"
if ($allowUnsignedRequested) {
  # The bundled development package is intentionally unsigned. Windows still
  # rejects an unsigned MSIX with -ExternalLocation (0x80073D2C), even when
  # -AllowUnsigned is supplied, so register the loose manifest instead.
  $manifest = Update-StagedSparsePackage
  Write-Host "Register loose sparse manifest with ExternalLocation: $ExternalLocation"
  Write-Host "Manifest staging path: $manifest"
  Add-AppxPackage -Register $manifest -ExternalLocation $ExternalLocation -ForceUpdateFromAnyVersion -ForceApplicationShutdown
  exit 0
}

$identityPackage = Resolve-IdentityPackagePath
if (-not [string]::IsNullOrWhiteSpace($identityPackage)) {
  Write-Host "Register sparse identity package with ExternalLocation: $ExternalLocation"
  Write-Host "Identity package: $identityPackage"
  $args = @(
    "-Path", $identityPackage,
    "-ExternalLocation", $ExternalLocation,
    "-ForceUpdateFromAnyVersion",
    "-ForceApplicationShutdown"
  )
  Add-AppxPackage @args
  exit 0
}

$manifest = Update-StagedSparsePackage

Write-Host "Register loose sparse manifest with ExternalLocation: $ExternalLocation"
Write-Host "Manifest staging path: $manifest"
Write-Warning "No signed sparse MSIX was found. Loose manifest registration is intended for local development and may fail on clean end-user machines."
Add-AppxPackage -Register $manifest -ExternalLocation $ExternalLocation -ForceUpdateFromAnyVersion -ForceApplicationShutdown
