#pragma once
#include <windows.h>
#include <string>
#include <stdexcept>

namespace test_support {
inline void Require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

class RegistryFixture {
 public:
  RegistryFixture() {
    path_ = L"Software\\VertreeIconTests\\" + std::to_wstring(GetCurrentProcessId());
    Require(RegOpenCurrentUser(KEY_ALL_ACCESS, &user_) == ERROR_SUCCESS, "open user registry");
    Require(RegCreateKeyExW(user_, path_.c_str(), 0, nullptr, 0, KEY_ALL_ACCESS,
        nullptr, &root_, nullptr) == ERROR_SUCCESS, "create isolated registry");
    Require(RegCreateKeyExW(root_, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        0, nullptr, 0, KEY_ALL_ACCESS, nullptr, &preferences_, nullptr) == ERROR_SUCCESS, "create preferences");
    Require(RegOverridePredefKey(HKEY_CURRENT_USER, root_) == ERROR_SUCCESS, "override registry in this process");
  }
  ~RegistryFixture() {
    RegOverridePredefKey(HKEY_CURRENT_USER, nullptr);
    RegCloseKey(preferences_);
    RegCloseKey(root_);
    RegDeleteTreeW(user_, path_.c_str());
    RegCloseKey(user_);
  }
  void Set(const wchar_t* name, DWORD value) {
    Require(RegSetValueExW(preferences_, name, 0, REG_DWORD,
        reinterpret_cast<const BYTE*>(&value), sizeof(value)) == ERROR_SUCCESS, "set theme");
  }
 private:
  HKEY user_ = nullptr, root_ = nullptr, preferences_ = nullptr;
  std::wstring path_;
};

}
