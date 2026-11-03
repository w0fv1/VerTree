#include "shell_icons.h"
#include "resource.h"
#include <utility>

ShellIcons::ShellIcons(HWND window, HINSTANCE instance,
    std::function<void(const std::string&)> on_changed)
    : window_(window), instance_(instance), on_changed_(std::move(on_changed)) {
  Refresh(GetDpiForWindow(window_));
}

ShellIcons::~ShellIcons() {
  if (IsWindow(window_)) {
    SendMessageW(window_, WM_SETICON, ICON_SMALL, 0);
    SendMessageW(window_, WM_SETICON, ICON_BIG, 0);
  }
  if (small_) DestroyIcon(small_);
  if (large_) DestroyIcon(large_);
}

std::string ShellIcons::asset() const {
  return dark_ ? "assets/img/logo/logo-dark.ico" : "assets/img/logo/logo-light.ico";
}

void ShellIcons::HandleMessage(UINT message, WPARAM wparam) {
  switch (message) {
    case WM_DPICHANGED:
      Refresh(HIWORD(wparam));
      break;
    case WM_SETTINGCHANGE:
    case WM_THEMECHANGED:
    case WM_DWMCOLORIZATIONCOLORCHANGED:
      Refresh(GetDpiForWindow(window_));
      break;
  }
}

void ShellIcons::Refresh(UINT dpi) {
  DWORD light = 1;
  DWORD size = sizeof(light);
  RegGetValueW(HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &size);
  const bool dark = light == 0;
  const auto resource = MAKEINTRESOURCEW(dark ? IDI_APP_ICON_DARK : IDI_APP_ICON_LIGHT);
  const auto small_icon = static_cast<HICON>(LoadImageW(instance_, resource, IMAGE_ICON,
      GetSystemMetricsForDpi(SM_CXSMICON, dpi), GetSystemMetricsForDpi(SM_CYSMICON, dpi), 0));
  const auto large_icon = static_cast<HICON>(LoadImageW(instance_, resource, IMAGE_ICON,
      GetSystemMetricsForDpi(SM_CXICON, dpi), GetSystemMetricsForDpi(SM_CYICON, dpi), 0));
  if (!small_icon || !large_icon) {
    if (small_icon) DestroyIcon(small_icon);
    if (large_icon) DestroyIcon(large_icon);
    return;
  }
  SendMessageW(window_, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(small_icon));
  SendMessageW(window_, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(large_icon));
  if (small_) DestroyIcon(small_);
  if (large_) DestroyIcon(large_);
  small_ = small_icon;
  large_ = large_icon;
  if (dark_ != dark) {
    dark_ = dark;
    on_changed_(asset());
  }
}
