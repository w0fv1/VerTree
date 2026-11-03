#include "../shell_icons.h"
#include "../resource.h"
#include <stdexcept>
#include <iostream>
#include <vector>

void Require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

std::vector<BYTE> IconPixels(HICON icon, int size) {
  ICONINFO info{};
  Require(GetIconInfo(icon, &info) != 0, "read icon bitmap");
  BITMAP bitmap{};
  GetObjectW(info.hbmColor, sizeof(bitmap), &bitmap);
  Require(bitmap.bmWidth == size && bitmap.bmHeight == size, "icon dimensions match DPI");
  BITMAPINFO format{};
  format.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  format.bmiHeader.biWidth = size;
  format.bmiHeader.biHeight = -size;
  format.bmiHeader.biPlanes = 1;
  format.bmiHeader.biBitCount = 32;
  format.bmiHeader.biCompression = BI_RGB;
  std::vector<BYTE> pixels(size * size * 4);
  const auto dc = CreateCompatibleDC(nullptr);
  const auto rows = GetDIBits(dc, info.hbmColor, 0, size, pixels.data(), &format, DIB_RGB_COLORS);
  DeleteDC(dc);
  DeleteObject(info.hbmColor);
  DeleteObject(info.hbmMask);
  Require(rows == size, "read icon pixels");
  return pixels;
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

int main() {
  try {
    RegistryFixture registry;
    const auto instance = GetModuleHandleW(nullptr);
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = DefWindowProcW;
    window_class.hInstance = instance;
    window_class.lpszClassName = L"VertreeShellIconTest";
    Require(RegisterClassW(&window_class) != 0, "register window");
    const auto window = CreateWindowW(window_class.lpszClassName, L"", WS_OVERLAPPEDWINDOW,
        0, 0, 300, 300, nullptr, nullptr, instance, nullptr);
    Require(window != nullptr, "create window");
    std::vector<std::string> changes;
    ShellIcons icons(window, instance, [&](const auto& asset) { changes.push_back(asset); });
    Require(icons.asset() == "assets/img/logo/logo-light.ico", "missing preference uses light shell");
    registry.Set(L"AppsUseLightTheme", 1);
    registry.Set(L"SystemUsesLightTheme", 0);
    icons.HandleMessage(WM_SETTINGCHANGE, 0);
    Require(icons.asset() == "assets/img/logo/logo-dark.ico", "system dark beats app light");
    Require(changes.size() == 1, "one theme notification");
    icons.HandleMessage(WM_THEMECHANGED, 0);
    Require(changes.size() == 1, "unchanged theme does not notify");
    for (const UINT dpi : {96U, 144U, 192U}) {
      icons.HandleMessage(WM_DPICHANGED, MAKEWPARAM(dpi, dpi));
      for (const auto kind : {ICON_SMALL, ICON_BIG}) {
        const auto actual = reinterpret_cast<HICON>(SendMessageW(window, WM_GETICON, kind, 0));
        const int size = GetSystemMetricsForDpi(kind == ICON_BIG ? SM_CXICON : SM_CXSMICON, dpi);
        const auto expected = static_cast<HICON>(LoadImageW(instance, MAKEINTRESOURCEW(IDI_APP_ICON_DARK),
            IMAGE_ICON, size, size, 0));
        Require(expected != nullptr && actual != nullptr, "icons exist");
        const bool matches = IconPixels(actual, size) == IconPixels(expected, size);
        DestroyIcon(expected);
        Require(matches, "DPI-sized dark resource is installed");
      }
    }
    registry.Set(L"AppsUseLightTheme", 0);
    registry.Set(L"SystemUsesLightTheme", 1);
    icons.HandleMessage(WM_SETTINGCHANGE, 0);
    Require(icons.asset() == "assets/img/logo/logo-light.ico", "system light beats app dark");
    Require(changes.size() == 2, "light transition notifies tray");
    DestroyWindow(window);
    UnregisterClassW(window_class.lpszClassName, instance);
    std::cout << "Shell theme, mixed themes, notifications and DPI resources passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
