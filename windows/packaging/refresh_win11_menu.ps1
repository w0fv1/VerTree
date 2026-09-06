param(
  [ValidateSet("Debug","Profile","Release")]
  [string]$BuildMode = "Release",
  [string]$ExternalLocation = "",
  [switch]$RestartExplorer,
  [switch]$KillDllHost
)

$ErrorActionPreference = "Stop"

function Restart-Explorer {
  Write-Host "Restart Explorer..."
  Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 800
  Start-Process explorer.exe | Out-Null
}

if ([string]::IsNullOrWhiteSpace($ExternalLocation)) {
  $ExternalLocation = (Resolve-Path (Join-Path $PSScriptRoot "..\\..\\build\\windows\\x64\\runner\\$BuildMode")).Path
}

if (-not (Test-Path $ExternalLocation)) {
  Write-Error "ExternalLocation not found: $ExternalLocation"
}

$installScript = Join-Path $PSScriptRoot "install_sparse_package.ps1"
if (-not (Test-Path $installScript)) {
  Write-Error "install_sparse_package.ps1 not found: $installScript"
}

Write-Host "Refresh Win11 context menu (sparse package)"
Write-Host "ExternalLocation=$ExternalLocation"

& $installScript -ExternalLocation $ExternalLocation -Force

if ($KillDllHost) {


  try {
    Write-Host "Taskkill DllHost with module vertree_context_menu.dll..."
    & taskkill.exe /F /IM dllhost.exe /FI "MODULES eq vertree_context_menu.dll" | Out-Null
  } catch {
    Write-Warning "Failed to taskkill dllhost with module filter: $($_.Exception.Message)"
  }
}

if ($RestartExplorer) {
  Restart-Explorer
}

Write-Host "Done. If the menu still doesn't refresh, log off/on once."

