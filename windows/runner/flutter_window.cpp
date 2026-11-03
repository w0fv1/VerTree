#include "flutter_window.h"
#include "utils.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();



  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);

  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  file_tools_picker_ = RegisterFileToolsPicker(flutter_controller_->engine()->messenger(), GetHandle());
  shell_icons_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "vertree/shell-icons",
      &flutter::StandardMethodCodec::GetInstance());
  shell_icons_ = std::make_unique<ShellIcons>(GetHandle(), GetModuleHandleW(nullptr),
      [this](const std::string& asset) {
        shell_icons_channel_->InvokeMethod("iconChanged", std::make_unique<flutter::EncodableValue>(asset));
      }, [this](int resource) {
        if (FAILED(shell_shortcuts_.Sync(resource))) OutputDebugStringW(L"Vertree shortcut synchronization failed\n");
      });
  shell_icons_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "currentIcon") {
      result->Success(flutter::EncodableValue(shell_icons_->asset()));
    } else if (call.method_name() == "appIdentity") {
      result->Success(flutter::EncodableValue(Utf8FromUtf16(ShellShortcuts::kAppId)));
    } else {
      result->NotImplemented();
    }
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());



  return true;
}

void FlutterWindow::OnDestroy() {
  shell_icons_.reset();
  shell_icons_channel_.reset();
  file_tools_picker_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (shell_icons_) shell_icons_->HandleMessage(message, wparam);

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
