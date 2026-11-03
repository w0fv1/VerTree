#pragma once
#include <filesystem>
#include <windows.h>

class ShellShortcuts {
 public:
  inline static constexpr wchar_t kAppId[] = L"dev.w0fv1.vertree.desktop";
  ShellShortcuts();
  ShellShortcuts(std::filesystem::path executable, std::filesystem::path programs,
                 std::filesystem::path pinned, std::filesystem::path desktop = {});
  HRESULT Sync(int icon_resource);

 private:
  std::filesystem::path executable_;
  std::filesystem::path programs_;
  std::filesystem::path pinned_;
  std::filesystem::path desktop_;
};
