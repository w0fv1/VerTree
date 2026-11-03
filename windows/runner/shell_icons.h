#pragma once
#include <windows.h>
#include <functional>
#include <string>

class ShellIcons {
 public:
  ShellIcons(HWND window, HINSTANCE instance, std::function<void(const std::string&)> on_changed);
  ~ShellIcons();
  ShellIcons(const ShellIcons&) = delete;
  ShellIcons& operator=(const ShellIcons&) = delete;
  void HandleMessage(UINT message, WPARAM wparam);
  std::string asset() const;

 private:
  void Refresh(UINT dpi);
  HWND window_;
  HINSTANCE instance_;
  std::function<void(const std::string&)> on_changed_;
  bool dark_ = false;
  HICON small_ = nullptr;
  HICON large_ = nullptr;
};
