#include "../shell_icons.h"
#include "../resource.h"
#include <stdexcept>
#include <iostream>
#include <vector>
#include "../../test_support/theme_registry.h"
#include <propkey.h>
#include <propvarutil.h>
#include <shobjidl.h>
#include <wrl/client.h>

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

void RequireTaskbarIcon(HWND window, int resource) {
  Microsoft::WRL::ComPtr<IPropertyStore> properties;
  Require(SUCCEEDED(SHGetPropertyStoreForWindow(window, IID_PPV_ARGS(&properties))), "read taskbar properties");
  PROPVARIANT value{};
  Require(SUCCEEDED(properties->GetValue(PKEY_AppUserModel_RelaunchIconResource, &value)), "read taskbar icon");
  wchar_t executable[32768];
  GetModuleFileNameW(nullptr, executable, 32768);
  const auto expected = std::wstring(executable) + L",-" + std::to_wstring(resource);
  const bool matches = value.vt == VT_LPWSTR && expected == value.pwszVal;
  PropVariantClear(&value);
  Require(matches, "taskbar relaunch icon must match the selected theme resource");
}


int main() {
  try {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    test_support::RegistryFixture registry;
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
    std::vector<int> resources;
    ShellIcons icons(window, instance, [&](const auto& asset) { changes.push_back(asset); },
        [&](int resource) { resources.push_back(resource); });
    Require(resources == std::vector<int>{IDI_APP_ICON_LIGHT}, "initial shortcut theme is published");
    Require(icons.asset() == "assets/img/logo/logo-light.ico", "missing preference uses light shell");
    RequireTaskbarIcon(window, IDI_APP_ICON_LIGHT);
    registry.Set(L"AppsUseLightTheme", 1);
    registry.Set(L"SystemUsesLightTheme", 0);
    icons.HandleMessage(WM_SETTINGCHANGE, 0);
    Require(icons.asset() == "assets/img/logo/logo-dark.ico", "system dark beats app light");
    RequireTaskbarIcon(window, IDI_APP_ICON_DARK);
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
    RequireTaskbarIcon(window, IDI_APP_ICON_LIGHT);
    Require(changes.size() == 2, "light transition notifies tray");
    Require(resources == std::vector<int>{IDI_APP_ICON_LIGHT, IDI_APP_ICON_DARK, IDI_APP_ICON_LIGHT}, "shortcut updates follow theme transitions, not DPI or duplicate events");
    DestroyWindow(window);
    UnregisterClassW(window_class.lpszClassName, instance);
    std::cout << "Shell theme, mixed themes, notifications and DPI resources passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
