param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$InstallOnCI
)

$ErrorActionPreference = 'Stop'
$packagePath = (Resolve-Path -LiteralPath $Path).Path
$installer = New-Object -ComObject WindowsInstaller.Installer
$installer.UILevel = 2
$session = $installer.OpenPackage($packagePath, 1)
foreach ($action in @('CostInitialize', 'FileCost', 'CostFinalize')) {
    if ($session.DoAction($action) -ne 1) { throw "MSI $action failed: $packagePath" }
}

$desktop = $session.Property('DesktopFolder')
$programMenu = $session.Property('ProgramMenuFolder')
$installDir = $session.Property('INSTALLDIR')
$menuDir = $session.Property('ProgramMenuDir')
if ($session.Property('ALLUSERS') -ne '1') { throw 'MSI must install per machine.' }
if ($menuDir.TrimEnd('\') -ne (Join-Path $programMenu 'Vertree')) {
    throw "Start menu resolves incorrectly: $menuDir; expected $programMenu\Vertree"
}
$db = $installer.OpenDatabase($packagePath, 0)
$view = $db.OpenView('SELECT `Directory_` FROM `Shortcut` WHERE `Shortcut` = ''DesktopShortcut''')
$view.Execute()
$record = $view.Fetch()
if ($null -eq $record -or $record.StringData(1) -ne 'DesktopFolder') {
    throw 'Desktop shortcut does not use the standard DesktopFolder property.'
}
$view.Close()
if ([string]::IsNullOrWhiteSpace($desktop) -or $desktop -eq [IO.Path]::GetPathRoot($desktop)) {
    throw "Desktop resolves incorrectly: $desktop"
}
Write-Host "MSI directory validation passed: $packagePath"
foreach ($comObject in @($record, $view, $db, $session, $installer)) {
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject)
}
if (-not $InstallOnCI) { return }
if ($env:GITHUB_ACTIONS -ne 'true') {
    throw '-InstallOnCI is restricted to disposable GitHub Actions runners.'
}
if (Test-Path -LiteralPath $installDir) { throw "Install directory already exists: $installDir" }

$logDir = Join-Path $env:RUNNER_TEMP 'vertree-msi-test'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$installLog = Join-Path $logDir 'install.log'
$uninstallLog = Join-Path $logDir 'uninstall.log'
$installed = $false
try {
    $process = Start-Process msiexec.exe -WindowStyle Hidden -Wait -PassThru -ArgumentList @(
        '/i', "`"$packagePath`"", '/qn', '/norestart', 'REBOOT=ReallySuppress', '/L*v', "`"$installLog`""
    )
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "MSI install failed with $($process.ExitCode). See $installLog"
    }
    $installed = $true
    $executable = Join-Path $installDir 'vertree.exe'
    if (-not (Test-Path -LiteralPath $executable)) { throw "Missing installed executable: $executable" }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcut in @((Join-Path $desktop 'Vertree.lnk'), (Join-Path $menuDir 'Vertree.lnk'))) {
        if (-not (Test-Path -LiteralPath $shortcut)) { throw "Missing shortcut: $shortcut" }
        if ($shell.CreateShortcut($shortcut).TargetPath -ne $executable) {
            throw "Incorrect shortcut target: $shortcut"
        }
    }
} finally {
    if ($installed) {
        $process = Start-Process msiexec.exe -WindowStyle Hidden -Wait -PassThru -ArgumentList @(
            '/x', "`"$packagePath`"", '/qn', '/norestart', 'REBOOT=ReallySuppress', '/L*v', "`"$uninstallLog`""
        )
        if ($process.ExitCode -notin @(0, 3010)) { throw "MSI uninstall failed: $($process.ExitCode)" }
        if (Test-Path -LiteralPath (Join-Path $installDir 'vertree.exe')) { throw 'Uninstall left the executable installed.' }
    }
}
Write-Host 'MSI install, shortcut, and uninstall smoke test passed.'
