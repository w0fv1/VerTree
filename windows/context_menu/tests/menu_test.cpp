// Exercises the shell COM surface without registering it or launching Explorer.
#define VERTREE_CONTEXT_MENU_TESTS
#include "../vertree_context_menu.cpp"
#include <iostream>
#include <stdexcept>
#include "../../test_support/theme_registry.h"

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

int main() {
  try {
    Require(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)), "COM init");
    const std::vector<std::wstring> order{L"preview", L"viewtree", L"express-backup", L"monit", L"share", L"conversion", L"unlock", L"fast-delete"};
    Require(_countof(kMenuCommands) == order.size(), "eight requested commands");
    for (size_t index = 0; index < order.size(); ++index) Require(kMenuCommands[index].verb == order[index], "requested command order");
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

    Require(GetIconResourceIdForVerb(L"unlock") != GetIconResourceIdForVerb(L"viewtree"), "file usage has its own icon");
    Require(GetIconResourceIdForVerb(L"fast-delete") != GetIconResourceIdForVerb(L"viewtree"), "delete has its own icon");
    Require(GetIconResourceIdForVerb(L"conversion") != GetIconResourceIdForVerb(L"viewtree"), "conversion has its own icon");

    {
      test_support::RegistryFixture registry;
      for (DWORD light : {0UL, 1UL}) {
        registry.Set(L"AppsUseLightTheme", light);
        registry.Set(L"SystemUsesLightTheme", light == 0 ? 1 : 0);
        const int root_icon = IDI_VERTREE_ROOT + (light == 0 ? VERTREE_DARK_ICON_OFFSET : 0);
        const auto root_spec = BuildModuleIconSpec(IDI_VERTREE_ROOT);
        Require(root_spec.substr(root_spec.find_last_of(L',') + 1) == L"-" + std::to_wstring(root_icon), "root logo follows Explorer theme");
        HICON root_image = static_cast<HICON>(LoadImageW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(root_icon), IMAGE_ICON, 32, 32, 0));
        Require(root_image != nullptr, "root logo theme resource exists");
        DestroyIcon(root_image);
        for (const auto& definition : kMenuCommands) {
          const auto spec = BuildModuleIconSpec(definition.icon);
          const int selected = definition.icon + (light == 0 ? VERTREE_DARK_ICON_OFFSET : 0);
          Require(spec.substr(spec.find_last_of(L',') + 1) == L"-" + std::to_wstring(selected), "Explorer theme selects menu resource independent of taskbar theme");
          HICON icon = nullptr;
          const auto module = GetModuleHandleW(nullptr);
          icon = static_cast<HICON>(LoadImageW(module, MAKEINTRESOURCEW(selected), IMAGE_ICON, 32, 32, 0));
          Require(icon != nullptr, "selected menu icon exists in module");
          DestroyIcon(icon);
        }
      }
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
    Require(total == 8 && count == 0, "eight menu actions and clean end");
    Require(SUCCEEDED(commands->Reset()), "enumerator reset");
    Require(commands->Next(1, &command, &count) == S_OK, "enumerator reopen");
    command->Release();
    commands->Release();
    root->Release();
    Require(DllCanUnloadNow() == S_OK, "COM objects released");
    CoUninitialize();
    std::cout << "PASS: eight shell actions, preview first, argument round trips, COM lifecycle\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
