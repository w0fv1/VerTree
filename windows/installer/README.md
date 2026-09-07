# MSI packaging checks

`Product.wxs` installs per machine. Use the standard `ProgramMenuFolder` and
`DesktopFolder` directory identifiers: Windows Installer resolves their shared
locations when `ALLUSERS=1`. `CommonProgramsFolder` and `CommonDesktopFolder` are
not standard MSI properties and previously resolved to the drive root.

Non-advertised shortcut components use HKCU registry key paths, as required by
WiX ICE38/ICE43 validation. Do not suppress ICE validation to bypass incorrect
component authoring.

References: [Microsoft directory properties](https://learn.microsoft.com/en-us/windows/win32/msi/installation-context),
[WiX shortcut authoring](https://docs.firegiant.com/wix3/howtos/files_and_registry/create_start_menu_shortcut/).

`windows/build.ps1` runs the package directory check after linking:

```powershell
./windows/installer/Test-Msi.ps1 -Path ./windows/vertree-windows-x64-1.2.0.msi
```

This opens an MSI session and performs costing only; it does not install the app.
The Release workflow additionally uses `-InstallOnCI` on its disposable Windows
runner to install, verify the executable and both shortcuts, and uninstall.
Install and uninstall logs are uploaded even when the check fails. The install
test deliberately refuses to run outside GitHub Actions or over an existing
installation directory.

For a user-specific installation failure, capture the exact Windows Installer
error with the user's chosen package:

```powershell
msiexec.exe /i "C:\Downloads\vertree-windows-x64-1.2.0.msi" /L*v "$env:TEMP\vertree-msi-install.log"
```

This command performs an actual interactive installation. The log near
`Return value 3`, together with the final exit code, distinguishes permission,
upgrade, policy and package problems. A costing check alone does not prove a
full installation succeeds on the user's machine.
