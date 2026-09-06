// Exercises the shell COM surface without registering it or launching Explorer.
#include "../vertree_context_menu.cpp"
#include <iostream>
#include <stdexcept>

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

int main() {
  try {
    Require(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)), "COM init");
    const std::wstring path = L"C:\\预览 测试\\report & final.docx";
    for (const auto& command : kMenuCommands) {
      const std::wstring line = L"\"C:\\Program Files\\Vertree\\vertree.exe\" " +
          BuildArgs(command.verb, path);
      int argc = 0;
      LPWSTR* argv = CommandLineToArgvW(line.c_str(), &argc);
      Require(argv && argc == 3, "command argument count");
      Require(argv[1] == std::wstring(command.verb), "command verb");
      Require(argv[2] == path, "Unicode and spaced file path round trip");
      LocalFree(argv);
    }

    CLSID clsid;
    Require(SUCCEEDED(CLSIDFromString(kClsid, &clsid)), "CLSID");
    IClassFactory* factory = nullptr;
    Require(SUCCEEDED(DllGetClassObject(clsid, IID_PPV_ARGS(&factory))), "class factory");
    IExplorerCommand* root = nullptr;
    Require(SUCCEEDED(factory->CreateInstance(nullptr, IID_PPV_ARGS(&root))), "root command");
    factory->Release();
    EXPCMDFLAGS flags;
    Require(SUCCEEDED(root->GetFlags(&flags)) && flags == ECF_HASSUBCOMMANDS, "submenu flag");
    IEnumExplorerCommand* commands = nullptr;
    Require(SUCCEEDED(root->EnumSubCommands(&commands)), "enumeration");
    IExplorerCommand* command = nullptr;
    ULONG count = 0;
    int total = 0;
    while (commands->Next(1, &command, &count) == S_OK) {
      LPWSTR title = nullptr;
      Require(SUCCEEDED(command->GetTitle(nullptr, &title)) && title && *title, "title");
      if (total == 0) {
        const std::wstring value(title);
        Require(value == L"预览文件" || value == L"Preview file" ||
                value == L"ファイルをプレビュー", "preview first");
      }
      CoTaskMemFree(title);
      LPWSTR icon = nullptr;
      Require(SUCCEEDED(command->GetIcon(nullptr, &icon)) && icon && *icon, "icon");
      CoTaskMemFree(icon);
      command->Release();
      ++total;
    }
    Require(total == 6 && count == 0, "six menu actions and clean end");
    Require(SUCCEEDED(commands->Reset()), "enumerator reset");
    Require(commands->Next(1, &command, &count) == S_OK, "enumerator reopen");
    command->Release();
    commands->Release();
    root->Release();
    Require(DllCanUnloadNow() == S_OK, "COM objects released");
    CoUninitialize();
    std::cout << "PASS: six shell actions, preview first, argument round trips, COM lifecycle\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
