#include "../shell_shortcuts.h"
#include <shobjidl.h>
#include <propkey.h>
#include <propvarutil.h>
#include <wrl/client.h>
#include <iostream>
#include <stdexcept>
#include <string>

using Microsoft::WRL::ComPtr;

void Require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

void Check(const std::filesystem::path& path, const std::filesystem::path& target, int resource) {
  ComPtr<IShellLinkW> link;
  Require(SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link))), "create shell link reader");
  ComPtr<IPersistFile> file;
  link.As(&file);
  Require(SUCCEEDED(file->Load(path.c_str(), STGM_READ)), "read saved shortcut");
  wchar_t value[32768];
  int icon = 0;
  link->GetIconLocation(value, 32768, &icon);
  Require(target == value && icon == -resource, "shortcut uses selected embedded resource");
  link->GetPath(value, 32768, nullptr, SLGP_RAWPATH);
  Require(target == value, "shortcut targets current installed executable");
  ComPtr<IPropertyStore> properties;
  link.As(&properties);
  PROPVARIANT id{};
  properties->GetValue(PKEY_AppUserModel_ID, &id);
  const bool matches = id.vt == VT_LPWSTR && std::wstring(id.pwszVal) == ShellShortcuts::kAppId;
  PropVariantClear(&id);
  Require(matches, "shortcut shares the window identity");
}

int main() {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const auto root = std::filesystem::temp_directory_path() / (L"VertreeShortcutTest-" + std::to_wstring(GetCurrentProcessId()));
  try {
    const auto programs = root / L"Programs";
    const auto pinned = root / L"Pinned";
    const auto desktop = root / L"Desktop";
    const auto executable = root / L"Vertree.exe";
    ShellShortcuts shortcuts(executable, programs, pinned, desktop);
    Require(SUCCEEDED(shortcuts.Sync(103)), "initial shortcut creation");
    Check(programs / L"Vertree.lnk", executable, 103);
    std::filesystem::create_directories(pinned);
    std::filesystem::create_directories(desktop);
    std::filesystem::copy_file(programs / L"Vertree.lnk", desktop / L"Vertree.lnk");
    std::filesystem::copy_file(programs / L"Vertree.lnk", pinned / L"User renamed.lnk");
    ShellShortcuts other(root / L"Other.exe", root / L"OtherPrograms", root / L"OtherPinned");
    Require(SUCCEEDED(other.Sync(101)), "unrelated fixture");
    std::filesystem::copy_file(root / L"OtherPrograms/Vertree.lnk", pinned / L"Other.lnk");
    Require(SUCCEEDED(shortcuts.Sync(102)), "light theme update");
    Check(programs / L"Vertree.lnk", executable, 102);
    Check(pinned / L"User renamed.lnk", executable, 102);
    Check(desktop / L"Vertree.lnk", executable, 102);
    Check(pinned / L"Other.lnk", root / L"Other.exe", 101);
    const auto stamp = std::filesystem::last_write_time(programs / L"Vertree.lnk");
    Require(SUCCEEDED(shortcuts.Sync(102)), "unchanged theme");
    Require(stamp == std::filesystem::last_write_time(programs / L"Vertree.lnk"), "unchanged shortcut is not rewritten");
    std::filesystem::remove_all(root);
    std::cout << "Shortcut identity, theme changes, pinned copies and unrelated targets passed\n";
    CoUninitialize();
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    std::filesystem::remove_all(root);
    CoUninitialize();
    return 1;
  }
}
