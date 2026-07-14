#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

BOOL isAlreadyRunning();

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {

    BOOL alreadyRunning = isAlreadyRunning();
  if(alreadyRunning){

  }


  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);


  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Size size(600, 600);
  int screen_width = GetSystemMetrics(SM_CXSCREEN);
  int screen_height = GetSystemMetrics(SM_CYSCREEN);
  Win32Window::Point origin((screen_width - size.width) / 2,
                            (screen_height - size.height) / 2);
  if (!window.Create(L"vertree", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(false);


  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

BOOL isAlreadyRunning() {
    HANDLE hMutex = CreateMutex(NULL, TRUE, L"dev.w0fv1.vertree");
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        CloseHandle(hMutex);
        return TRUE;
    }
    (void)hMutex;
    return FALSE;
}
