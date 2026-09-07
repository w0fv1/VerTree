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
# Inspect the linked artifact: /qn installation alone cannot detect a missing wizard.
function Assert-MsiRow([string]$Query, [string]$Message) {
    $checkView = $null
    $checkRecord = $null
    try {
        $checkView = $db.OpenView($Query)
        $checkView.Execute()
        $checkRecord = $checkView.Fetch()
        if ($null -eq $checkRecord) { throw $Message }
    } catch {
        throw "$Message ($($_.Exception.Message))"
    } finally {
        if ($null -ne $checkView) { $checkView.Close() }
        foreach ($item in @($checkRecord, $checkView)) {
            if ($null -ne $item) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item) }
        }
    }
}
foreach ($dialog in @('WelcomeDlg', 'InstallDirDlg', 'VerifyReadyDlg', 'ProgressDlg',
                     'ExitDialog', 'MaintenanceWelcomeDlg', 'MaintenanceTypeDlg', 'FatalError', 'UserExit')) {
    Assert-MsiRow ('SELECT `Dialog` FROM `Dialog` WHERE `Dialog` = ''' + $dialog + '''') "Missing MSI dialog: $dialog"
}
foreach ($dialog in @('WelcomeDlg', 'MaintenanceWelcomeDlg', 'ExitDialog', 'FatalError', 'UserExit')) {
    Assert-MsiRow ('SELECT `Action` FROM `InstallUISequence` WHERE `Action` = ''' + $dialog + '''') "MSI dialog is not scheduled: $dialog"
}
Assert-MsiRow 'SELECT `Control` FROM `Control` WHERE `Dialog_` = ''ExitDialog'' AND `Control` = ''OptionalCheckBox''' 'Missing launch checkbox.'
Assert-MsiRow 'SELECT `Event` FROM `ControlEvent` WHERE `Dialog_` = ''ExitDialog'' AND `Control_` = ''Finish'' AND `Event` = ''DoAction'' AND `Argument` = ''LaunchApplication'' AND `Condition` = ''WIXUI_EXITDIALOGOPTIONALCHECKBOX = 1 AND NOT Installed AND NOT REMOVE''' 'Finish must launch only when opted in after installation.'
Assert-MsiRow 'SELECT `Action` FROM `CustomAction` WHERE `Action` = ''LaunchApplication'' AND `Target` = ''WixShellExec''' 'Missing application launch action.'
Assert-MsiRow 'SELECT `Event` FROM `ControlEvent` WHERE `Dialog_` = ''ExitDialog'' AND `Control_` = ''Finish'' AND `Argument` = ''SetLaunchTarget'' AND `Ordering` = 1' 'Finish must resolve the launch path before launching.'
if ($session.DoAction('SetLaunchTarget') -ne 1 -or
    $session.Property('WixShellExecTarget') -ne (Join-Path $installDir 'vertree.exe')) {
    throw 'Launch target does not resolve to the installed application.'
}
$launchSequence = $db.OpenView('SELECT `Action` FROM `InstallExecuteSequence` WHERE `Action` = ''LaunchApplication''')
$launchSequence.Execute()
if ($null -ne $launchSequence.Fetch()) { throw 'Application launch must not run during silent installation or uninstall.' }
$launchSequence.Close()
[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($launchSequence)
Write-Host 'MSI wizard, maintenance, completion, and opt-in launch validation passed.'
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
