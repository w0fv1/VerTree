[Setup]
AppId={{E3E58F5C-9E78-4A10-9F2B-76F968B8034C}}
AppName=Vertree
#ifndef AppVersion
#define AppVersion "0.0.0"
#endif
#ifndef AppVersionInfoVersion
#define AppVersionInfoVersion "0.0.0.0"
#endif
AppVersion={#AppVersion}
AppVerName=Vertree {#AppVersion}
AppPublisher=Vertree
AppPublisherURL=https://vertree.w0fv1.dev
AppSupportURL=https://vertree.w0fv1.dev
AppUpdatesURL=https://vertree.w0fv1.dev
DefaultDirName={commonpf}\Vertree
DisableProgramGroupPage=yes
DefaultGroupName=Vertree
OutputDir=.
#ifndef OutputBaseFilename
#define OutputBaseFilename "vertree-windows-x64-" + AppVersion + "-setup"
#endif
OutputBaseFilename={#OutputBaseFilename}
#ifndef BuildMode
#define BuildMode "Release"
#endif
SetupIconFile="..\build\windows\x64\runner\{#BuildMode}\data\flutter_assets\assets\img\logo\logo.ico"
UninstallDisplayIcon={app}\vertree.exe
UninstallDisplayName=Vertree
VersionInfoVersion={#AppVersionInfoVersion}
VersionInfoProductName=Vertree
VersionInfoCompany=Vertree
VersionInfoDescription=Vertree Installer
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
SetupLogging=yes

[Files]
Source: "..\build\windows\x64\runner\{#BuildMode}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{commonprograms}\Vertree"; Filename: "{app}\vertree.exe"; IconFilename: "{app}\data\flutter_assets\assets\img\logo\logo.ico"
Name: "{commonprograms}\Uninstall Vertree"; Filename: "{uninstallexe}"; IconFilename: "{app}\data\flutter_assets\assets\img\logo\logo.ico"
Name: "{commondesktop}\Vertree"; Filename: "{app}\vertree.exe"; IconFilename: "{app}\data\flutter_assets\assets\img\logo\logo.ico"

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\win11_packaging\install_sparse_package.ps1"" -ExternalLocation ""{app}"" -Force"; StatusMsg: "Registering Windows 11 context menu..."; Flags: runhidden waituntilterminated runasoriginaluser; Check: Win11PackagingScriptExists
Filename: "{app}\vertree.exe"; Description: "Launch Vertree"; Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]

function Win11PackagingScriptExists(): Boolean;
begin
  Result := FileExists(ExpandConstant('{app}\win11_packaging\install_sparse_package.ps1'));
end;

function Win11UninstallPackagingScriptExists(): Boolean;
begin
  Result := FileExists(ExpandConstant('{app}\win11_packaging\uninstall_sparse_package.ps1'));
end;

function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('taskkill.exe', '/f /im vertree.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;

procedure DeleteLegacyMenuKeys(RootKey: Integer);
begin
  RegDeleteKeyIncludingSubkeys(RootKey, 'Software\Classes\*\shell\RegistryVerTreeLegacyRoot');
  RegDeleteKeyIncludingSubkeys(RootKey, 'Software\Classes\*\shell\RegistryVerTreePreview');
  RegDeleteKeyIncludingSubkeys(RootKey, 'Software\Classes\*\shell\RegistryVerTreeBackup');
  RegDeleteKeyIncludingSubkeys(RootKey, 'Software\Classes\*\shell\RegistryVerTreeExpressBackup');
  RegDeleteKeyIncludingSubkeys(RootKey, 'Software\Classes\*\shell\RegistryVerTreeMonitor');
  RegDeleteKeyIncludingSubkeys(RootKey, 'Software\Classes\*\shell\RegistryVerTreeShare');
  RegDeleteKeyIncludingSubkeys(RootKey, 'Software\Classes\*\shell\RegistryVerTreeViewTree');
  RegDeleteKeyIncludingSubkeys(RootKey, 'Software\Classes\*\shell\备份文件 VerTree');
  RegDeleteKeyIncludingSubkeys(RootKey, 'Software\Classes\*\shell\快速备份文件 VerTree');
  RegDeleteKeyIncludingSubkeys(RootKey, 'Software\Classes\*\shell\监控文件变动 VerTree');
  RegDeleteKeyIncludingSubkeys(RootKey, 'Software\Classes\*\shell\查看文件版本树 VerTree');
end;

procedure DeleteRegistryKeys();
begin
  DeleteLegacyMenuKeys(HKEY_CURRENT_USER);
  DeleteLegacyMenuKeys(HKEY_LOCAL_MACHINE);
  RegDeleteKeyIncludingSubkeys(HKEY_CLASSES_ROOT, '*\shell\Vertree');
  RegDeleteKeyIncludingSubkeys(HKEY_CLASSES_ROOT, 'CLSID\{BFD9F3B4-3C8C-4B1C-8E57-1F4BA6A96F3E}');
  RegDeleteKeyIncludingSubkeys(HKEY_CLASSES_ROOT, '*\shellex\ContextMenuHandlers\Vertree');
  RegDeleteValue(HKEY_LOCAL_MACHINE, 'Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved', '{BFD9F3B4-3C8C-4B1C-8E57-1F4BA6A96F3E}');

  if RegValueExists(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'VerTree') then
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'VerTree');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    if Win11UninstallPackagingScriptExists() then
    begin
      ExecAsOriginalUser(
        'powershell.exe',
        '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\win11_packaging\uninstall_sparse_package.ps1') + '"',
        '',
        SW_HIDE,
        ewWaitUntilTerminated,
        ResultCode);
    end;
    DeleteRegistryKeys();
  end;
end;
