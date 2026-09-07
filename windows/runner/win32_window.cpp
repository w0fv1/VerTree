#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include "resource.h"

namespace {






#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";





constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";


static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);



int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

void SetWindowIcons(HWND window, UINT dpi) {
  // Provide current icons for the title bar and window switcher at this DPI.
  // LR_SHARED keeps these module resources valid for the process lifetime.
  const HINSTANCE instance = GetModuleHandle(nullptr);
  const auto set_icon = [window, instance, dpi](WPARAM kind, int metric) {
    const int size = GetSystemMetricsForDpi(metric, dpi);
    const HICON icon = static_cast<HICON>(LoadImage(
        instance, MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON, size, size,
        LR_SHARED));
    if (icon) {
      SendMessage(window, WM_SETICON, kind, reinterpret_cast<LPARAM>(icon));
    }
  };
  set_icon(ICON_SMALL, SM_CXSMICON);
  set_icon(ICON_BIG, SM_CXICON);
}

void SetTaskbarIdentity(HWND window) {
  Microsoft::WRL::ComPtr<IPropertyStore> properties;
  if (FAILED(SHGetPropertyStoreForWindow(window, IID_PPV_ARGS(&properties)))) {
    return;
  }

  wchar_t executable[32768];
  const DWORD length = GetModuleFileName(nullptr, executable, 32768);
  if (length == 0 || length >= 32768) {
    return;
  }
  const std::wstring path(executable, length);
  const std::wstring directory = path.substr(0, path.find_last_of(L"\\/"));
  const auto set_string = [&properties](REFPROPERTYKEY key,
                                        const std::wstring& text) {
    PROPVARIANT value;
    if (SUCCEEDED(InitPropVariantFromString(text.c_str(), &value))) {
      properties->SetValue(key, value);
      PropVariantClear(&value);
    }
  };

  // Keep the desktop window and installer shortcuts in the same taskbar group.
  // Explicit icon metadata avoids stale Shell/package icon associations after
  // an upgrade. Set relaunch metadata before the ID, as required by the Shell.
  set_string(PKEY_AppUserModel_RelaunchCommand, L"\"" + path + L"\"");
  set_string(PKEY_AppUserModel_RelaunchIconResource,
             directory + L"\\data\\flutter_assets\\assets\\img\\logo\\logo.ico,0");
  set_string(PKEY_AppUserModel_RelaunchDisplayNameResource, L"Vertree");
  set_string(PKEY_AppUserModel_ID, L"dev.w0fv1.vertree.desktop");
}

void ClearTaskbarIdentity(HWND window) {
  Microsoft::WRL::ComPtr<IPropertyStore> properties;
  if (SUCCEEDED(SHGetPropertyStoreForWindow(window, IID_PPV_ARGS(&properties)))) {
    const PROPVARIANT empty{};
    for (const auto& key : {PKEY_AppUserModel_ID,
                            PKEY_AppUserModel_RelaunchCommand,
                            PKEY_AppUserModel_RelaunchIconResource,
                            PKEY_AppUserModel_RelaunchDisplayNameResource}) {
      properties->SetValue(key, empty);
    }
  }
}



void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}


class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;


  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }



  const wchar_t* GetWindowClass();



  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  SetWindowIcons(window, dpi);
  SetTaskbarIdentity(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}


LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      ClearTaskbarIdentity(hwnd);
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      SetWindowIcons(hwnd, HIWORD(wparam));
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {

        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {

  return true;
}

void Win32Window::OnDestroy() {

}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
