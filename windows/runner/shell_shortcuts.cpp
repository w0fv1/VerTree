#include "shell_shortcuts.h"
#include <shlobj.h>
#include <propkey.h>
#include <propvarutil.h>
#include <wrl/client.h>
#include <vector>

using Microsoft::WRL::ComPtr;

ShellShortcuts::ShellShortcuts() {
  wchar_t executable[32768];
  const DWORD length = GetModuleFileNameW(nullptr, executable, 32768);
  if (length > 0 && length < 32768) executable_ = executable;
  PWSTR folder = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &folder))) {
    programs_ = folder;
    CoTaskMemFree(folder);
  }
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &folder))) {
    pinned_ = std::filesystem::path(folder) / L"Microsoft/Internet Explorer/Quick Launch/User Pinned/TaskBar";
    CoTaskMemFree(folder);
  }
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Desktop, 0, nullptr, &folder))) {
    desktop_ = folder;
    CoTaskMemFree(folder);
  }
}

ShellShortcuts::ShellShortcuts(std::filesystem::path executable,
    std::filesystem::path programs, std::filesystem::path pinned, std::filesystem::path desktop)
    : executable_(std::move(executable)), programs_(std::move(programs)), pinned_(std::move(pinned)), desktop_(std::move(desktop)) {}

HRESULT ShellShortcuts::Sync(int icon_resource) {
  if (executable_.empty() || programs_.empty()) return E_UNEXPECTED;
  std::error_code error;
  std::filesystem::create_directories(programs_, error);
  if (error) return HRESULT_FROM_WIN32(error.value());
  const auto primary = programs_ / L"Vertree.lnk";
  std::vector<std::filesystem::path> paths{primary};
  if (!desktop_.empty() && std::filesystem::exists(desktop_ / L"Vertree.lnk", error)) {
    paths.push_back(desktop_ / L"Vertree.lnk");
  }
  if (!pinned_.empty() && std::filesystem::exists(pinned_, error)) {
    for (const auto& entry : std::filesystem::directory_iterator(pinned_, error)) {
      if (entry.path().extension() == L".lnk") paths.push_back(entry.path());
    }
    if (error) return HRESULT_FROM_WIN32(error.value());
  }
  for (const auto& path : paths) {
    ComPtr<IShellLinkW> link;
    HRESULT result = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link));
    if (FAILED(result)) return result;
    ComPtr<IPersistFile> file;
    link.As(&file);
    const bool loaded = SUCCEEDED(file->Load(path.c_str(), STGM_READWRITE));
    wchar_t target[32768]{};
    if (loaded) link->GetPath(target, 32768, nullptr, SLGP_RAWPATH);
    const bool same_target = _wcsicmp(target, executable_.c_str()) == 0;
    if (path != primary && !same_target) continue;
    ComPtr<IPropertyStore> properties;
    link.As(&properties);
    PROPVARIANT identity{};
    properties->GetValue(PKEY_AppUserModel_ID, &identity);
    const bool same_identity = identity.vt == VT_LPWSTR && std::wstring(identity.pwszVal) == kAppId;
    PropVariantClear(&identity);
    wchar_t icon_path[32768]{};
    int index = 0;
    link->GetIconLocation(icon_path, 32768, &index);
    if (same_target && same_identity && index == -icon_resource &&
        _wcsicmp(icon_path, executable_.c_str()) == 0) continue;
    result = link->SetPath(executable_.c_str());
    if (SUCCEEDED(result)) result = link->SetWorkingDirectory(executable_.parent_path().c_str());
    if (SUCCEEDED(result)) result = link->SetIconLocation(executable_.c_str(), -icon_resource);
    if (SUCCEEDED(result)) result = InitPropVariantFromString(kAppId, &identity);
    if (SUCCEEDED(result)) result = properties->SetValue(PKEY_AppUserModel_ID, identity);
    PropVariantClear(&identity);
    if (SUCCEEDED(result)) result = properties->Commit();
    if (SUCCEEDED(result)) result = file->Save(path.c_str(), TRUE);
    if (FAILED(result)) return result;
    SHChangeNotify(loaded ? SHCNE_UPDATEITEM : SHCNE_CREATE,
        SHCNF_PATHW | SHCNF_FLUSH, path.c_str(), nullptr);
  }
  return S_OK;
}
