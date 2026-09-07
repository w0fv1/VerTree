param([string]$MakePri = "")

$ErrorActionPreference = "Stop"
$sparseRoot = Join-Path $PSScriptRoot "packaging/sparse"
$outputRoot = Join-Path $PSScriptRoot "../build/windows/icon_resources"
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

if ([string]::IsNullOrWhiteSpace($MakePri)) {
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits/10/bin"
    $sdk = Get-ChildItem -LiteralPath $sdkRoot -Directory |
        Where-Object { $_.Name -match '^10\.\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'x64/makepri.exe') } |
        Select-Object -First 1
    if ($null -eq $sdk) { throw "Install Windows SDK with x64 MakePri.exe." }
    $MakePri = Join-Path $sdk.FullName 'x64/makepri.exe'
}

$configPath = Join-Path $outputRoot "priconfig.xml"
& $MakePri createconfig /cf $configPath /dq en-US /o
if ($LASTEXITCODE -ne 0) { throw "MakePri configuration failed." }
& $MakePri new /pr $sparseRoot /cf $configPath /of (Join-Path $sparseRoot 'resources.pri') /in w0fv1.vertree /o
if ($LASTEXITCODE -ne 0) { throw "Taskbar icon resource indexing failed." }
