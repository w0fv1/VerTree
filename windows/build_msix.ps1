param(
    [ValidateSet("Debug","Profile","Release")]
    [string]$BuildMode = "Release",
    [string]$MakeAppx = ""
)

$ErrorActionPreference = "Stop"

function Get-PubspecVersion([string]$projectRoot) {
    $pubspec = Join-Path $projectRoot "pubspec.yaml"
    if (-not (Test-Path $pubspec)) {
        throw "pubspec.yaml not found at $pubspec"
    }
    $line = Select-String -Path $pubspec -Pattern '^\s*version:\s*(.+?)\s*$' | Select-Object -First 1
    if (-not $line) {
        throw "pubspec.yaml missing 'version:'"
    }
    $raw = $line.Matches[0].Groups[1].Value
    return $raw.Trim().Trim("'").Trim('"')
}

function Get-MsiProductVersion([string]$pubspecVersion) {
    $baseVersion = $pubspecVersion
    $preRelease = ""
    if ($pubspecVersion.Contains('-')) {
        $parts = $pubspecVersion.Split('-', 2)
        $baseVersion = $parts[0]
        $preRelease = $parts[1]
    }

    $baseParts = $baseVersion.Split('.')
    if ($baseParts.Length -lt 3) {
        return "0.0.0"
    }

    $major = [int]$baseParts[0]
    $minor = [int]$baseParts[1]
    $patch = [int]$baseParts[2]

    $patchBucket = $patch * 100
    $preOffset = 99
    if (-not [string]::IsNullOrWhiteSpace($preRelease)) {
        $preLower = $preRelease.ToLowerInvariant()
        $baseWeight = 0
        if ($preLower.StartsWith("alpha")) {
            $baseWeight = 0
        } elseif ($preLower.StartsWith("beta")) {
            $baseWeight = 30
        } elseif ($preLower.StartsWith("rc")) {
            $baseWeight = 60
        } else {
            $baseWeight = 80
        }

        $match = [regex]::Match($preLower, '(\d+)$')
        $ordinal = if ($match.Success) { [int]$match.Groups[1].Value } else { 0 }
        $preOffset = [Math]::Min($baseWeight + $ordinal, 98)
    }

    return "$major.$minor.$($patchBucket + $preOffset)"
}

function Get-MsixPackageVersion([string]$pubspecVersion) {
    $msiVersion = Get-MsiProductVersion -pubspecVersion $pubspecVersion
    $parts = $msiVersion.Split('.')
    if ($parts.Length -eq 3) {
        return "$msiVersion.0"
    }
    if ($parts.Length -eq 4) {
        return $msiVersion
    }
    return "0.0.0.0"
}

function Resolve-MakeAppx([string]$preferred) {
    if (-not [string]::IsNullOrWhiteSpace($preferred) -and (Test-Path $preferred)) {
        return $preferred
    }

    $cmd = Get-Command makeappx.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $kitsRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (-not (Test-Path $kitsRoot)) {
        return ""
    }

    $candidates = Get-ChildItem -Path $kitsRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending
    if ($candidates) {
        return $candidates[0].FullName
    }

    return ""
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
$pubspecVersion = Get-PubspecVersion -projectRoot $projectRoot
$msixPackageVersion = Get-MsixPackageVersion -pubspecVersion $pubspecVersion
$runnerOutputDir = (Resolve-Path (Join-Path $scriptDir "..\\build\\windows\\x64\\runner\\$BuildMode")).Path
$packagingSourceDir = Join-Path $scriptDir "packaging"
& (Join-Path $scriptDir 'build_icon_resources.ps1')
$msixBaseName = "vertree-windows-x64-$pubspecVersion"
$msixStageRoot = Join-Path $scriptDir "..\\build\\windows\\msix"
$msixStageDir = Join-Path $msixStageRoot "package"
$msixManifest = Join-Path $msixStageDir "AppxManifest.xml"
$msixPath = Join-Path $scriptDir "$msixBaseName.msix"
$makeAppxExe = Resolve-MakeAppx -preferred $MakeAppx

if (-not (Test-Path $runnerOutputDir)) {
    throw "Runner output directory not found: $runnerOutputDir"
}
if (-not (Test-Path $packagingSourceDir)) {
    throw "Packaging directory not found: $packagingSourceDir"
}
if ([string]::IsNullOrWhiteSpace($makeAppxExe)) {
    throw "MakeAppx.exe not found. Install Windows SDK or provide -MakeAppx."
}

if (Test-Path $msixStageDir) {
    Remove-Item $msixStageDir -Recurse -Force
}
if (Test-Path $msixPath) {
    Remove-Item $msixPath -Force
}

New-Item -ItemType Directory -Force -Path $msixStageDir | Out-Null
Copy-Item (Join-Path $runnerOutputDir "*") $msixStageDir -Recurse -Force
Copy-Item (Join-Path $packagingSourceDir "sparse\\*") $msixStageDir -Recurse -Force

if (-not (Test-Path $msixManifest)) {
    throw "MSIX manifest not found: $msixManifest"
}

$manifestContent = Get-Content $msixManifest -Raw
$manifestContent = $manifestContent.Replace('Version="1.0.0.0"', "Version=`"$msixPackageVersion`"")
[System.IO.File]::WriteAllText(
    $msixManifest,
    $manifestContent,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Using MakeAppx: $makeAppxExe"
Write-Host "Generating MSIX: $msixPath"
& $makeAppxExe pack /o /d $msixStageDir /p $msixPath
if ($LASTEXITCODE -ne 0 -or (-not (Test-Path $msixPath))) {
    throw "MSIX packaging failed."
}

Write-Host "MSIX package created: $msixPath"
