#include <windows.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <algorithm>
#include <string>
#include <vector>

#include "resource.h"

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")

namespace {

constexpr wchar_t kClsid[] = L"{BFD9F3B4-3C8C-4B1C-8E57-1F4BA6A96F3E}";
constexpr wchar_t kMenuTitle[] = L"Vertree";

struct MenuCommandDefinition {
  const wchar_t* verb;
  const wchar_t* zh;
  const wchar_t* en;
  const wchar_t* ja;
  int icon;
};

constexpr MenuCommandDefinition kMenuCommands[] = {
  {L"preview", L"预览文件", L"Preview file", L"ファイルをプレビュー", IDI_VERTREE_VIEWTREE},
  {L"backup", L"备份文件", L"Backup file", L"ファイルをバックアップ", IDI_VERTREE_BACKUP},
  {L"express-backup", L"快速备份文件", L"Quick backup", L"クイックバックアップ", IDI_VERTREE_EXPRESS_BACKUP},
  {L"monit", L"监控文件变动", L"Monitor file changes", L"ファイル変更を監視", IDI_VERTREE_MONITOR},
  {L"share", L"局域网分享下载", L"Share on LAN", L"LAN で共有", IDI_VERTREE_SHARE},
  {L"viewtree", L"查看文件版本树", L"View version tree", L"バージョンツリーを表示", IDI_VERTREE_VIEWTREE},
};

HINSTANCE g_instance = nullptr;
long g_module_lock = 0;

std::wstring GetTempLogPath() {
  wchar_t temp_path[MAX_PATH];
  DWORD len = GetTempPathW(MAX_PATH, temp_path);
  if (len == 0 || len >= MAX_PATH) {
    return L"";
  }
  std::wstring path(temp_path);
  path += L"vertree_context_menu.log";
  return path;
}

void LogLine(const std::wstring& message) {
  const std::wstring path = GetTempLogPath();
  if (path.empty()) return;
  HANDLE file = CreateFileW(
      path.c_str(),
      FILE_APPEND_DATA,
      FILE_SHARE_READ | FILE_SHARE_WRITE,
      nullptr,
      OPEN_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (file == INVALID_HANDLE_VALUE) return;

  SYSTEMTIME st;
  GetLocalTime(&st);
  wchar_t prefix[128];
  _snwprintf_s(prefix, _countof(prefix), _TRUNCATE,
               L"[%04d-%02d-%02d %02d:%02d:%02d.%03d] [pid=%lu tid=%lu] ",
               st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
               st.wMilliseconds, GetCurrentProcessId(), GetCurrentThreadId());
  std::wstring line = prefix + message + L"\r\n";
  DWORD bytes = 0;
  WriteFile(file, line.c_str(),
            static_cast<DWORD>(line.size() * sizeof(wchar_t)), &bytes, nullptr);
  FlushFileBuffers(file);
  CloseHandle(file);
}

void LogHr(const wchar_t* where, HRESULT hr) {
  wchar_t buf[256];
  _snwprintf_s(buf, _countof(buf), _TRUNCATE, L"%s hr=0x%08X", where, hr);
  LogLine(buf);
}

void LogFileLastWriteTime(const wchar_t* label, const std::wstring& path) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    LogLine(std::wstring(label) + L": <open failed>");
    return;
  }
  FILETIME ft;
  if (!GetFileTime(file, nullptr, nullptr, &ft)) {
    CloseHandle(file);
    LogLine(std::wstring(label) + L": <GetFileTime failed>");
    return;
  }
  CloseHandle(file);

  SYSTEMTIME utc;
  SYSTEMTIME local;
  if (!FileTimeToSystemTime(&ft, &utc) || !SystemTimeToTzSpecificLocalTime(nullptr, &utc, &local)) {
    LogLine(std::wstring(label) + L": <time convert failed>");
    return;
  }
  wchar_t buf[256];
  _snwprintf_s(buf, _countof(buf), _TRUNCATE, L"%s: %04d-%02d-%02d %02d:%02d:%02d.%03d",
               label, local.wYear, local.wMonth, local.wDay, local.wHour, local.wMinute,
               local.wSecond, local.wMilliseconds);
  LogLine(buf);
}

std::wstring GetModuleDir() {
  wchar_t path[MAX_PATH];
  if (!g_instance) {
    GetModuleFileNameW(nullptr, path, MAX_PATH);
  } else {
    GetModuleFileNameW(g_instance, path, MAX_PATH);
  }
  PathRemoveFileSpecW(path);
  return std::wstring(path);
}

std::wstring GetConfigPath() {
  wchar_t appdata[MAX_PATH];
  DWORD len = GetEnvironmentVariableW(L"APPDATA", appdata, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return L"";
  }
  std::wstring base(appdata);
  return base + L"\\dev.w0fv1\\vertree\\config.json";
}

bool ReadFileContent(const std::wstring& path, std::string& out) {
  HANDLE file = CreateFileW(
      path.c_str(),
      GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE,
      nullptr,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size;
  if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0) {
    CloseHandle(file);
    return false;
  }
  const DWORD bytes = static_cast<DWORD>(size.QuadPart);
  std::string buffer;
  buffer.resize(bytes);
  DWORD read = 0;
  const BOOL ok = ReadFile(file, buffer.data(), bytes, &read, nullptr);
  CloseHandle(file);
  if (!ok || read == 0) return false;
  out.assign(buffer.begin(), buffer.begin() + read);
  return true;
}

bool IsWin11MenuEnabled() {
  static LONG cached = -1;
  static ULONGLONG last_tick = 0;

  const ULONGLONG now = GetTickCount64();
  if (cached != -1 && (now - last_tick) < 1500) {
    return cached == 1;
  }
  last_tick = now;

  const std::wstring path = GetConfigPath();
  if (path.empty()) {
    cached = 1;
    return true;
  }
  std::string content;
  if (!ReadFileContent(path, content)) {
    cached = 1;
    return true;
  }
  const std::string key = "\"win11MenuEnabled\"";
  auto pos = content.find(key);
  if (pos == std::string::npos) {
    cached = 1;
    return true;
  }
  pos = content.find(":", pos + key.size());
  if (pos == std::string::npos) {
    cached = 1;
    return true;
  }
  auto next = content.find_first_not_of(" \t\r\n", pos + 1);
  if (next == std::string::npos) {
    cached = 1;
    return true;
  }
  if (content.compare(next, 4, "true") == 0) {
    cached = 1;
    return true;
  }
  if (content.compare(next, 5, "false") == 0) {
    cached = 0;
    return false;
  }
  cached = 1;
  return true;
}

std::string ReadConfigStringValue(const std::string& key, const std::string& default_value) {
  const std::wstring path = GetConfigPath();
  if (path.empty()) return default_value;
  std::string content;
  if (!ReadFileContent(path, content)) return default_value;

  const std::string quoted_key = "\"" + key + "\"";
  auto pos = content.find(quoted_key);
  if (pos == std::string::npos) return default_value;
  pos = content.find(":", pos + quoted_key.size());
  if (pos == std::string::npos) return default_value;
  auto next = content.find_first_not_of(" \t\r\n", pos + 1);
  if (next == std::string::npos) return default_value;
  if (content[next] != '"') return default_value;
  ++next;
  const auto end = content.find('"', next);
  if (end == std::string::npos || end <= next) return default_value;
  return content.substr(next, end - next);
}

enum class MenuLang {
  ZH_CN,
  EN,
  JA,
};

MenuLang GetMenuLang() {
  static ULONGLONG last_tick = 0;
  static MenuLang cached = MenuLang::ZH_CN;
  const ULONGLONG now = GetTickCount64();
  if ((now - last_tick) < 1500) return cached;
  last_tick = now;

  const std::string locale = ReadConfigStringValue("locale", "OTHER");
  if (locale == "en" || locale == "EN") {
    cached = MenuLang::EN;
  } else if (locale == "ja" || locale == "JA") {
    cached = MenuLang::JA;
  } else if (locale == "zhCn" || locale == "ZH_CN") {
    cached = MenuLang::ZH_CN;
  } else {

    const LANGID language = PRIMARYLANGID(GetUserDefaultUILanguage());
    cached = language == LANG_CHINESE ? MenuLang::ZH_CN : language == LANG_JAPANESE ? MenuLang::JA : MenuLang::EN;
  }
  return cached;
}

std::wstring GetCommandTitle(const wchar_t* verb) {
  const MenuLang lang = GetMenuLang();
  for (const auto& command : kMenuCommands) {
    if (wcscmp(verb, command.verb) == 0) {
      return lang == MenuLang::EN ? command.en : lang == MenuLang::JA ? command.ja : command.zh;
    }
  }
  return kMenuTitle;
}

std::wstring GetAppPath() {
  std::wstring dir = GetModuleDir();
  return dir + L"\\vertree.exe";
}

std::wstring GetSystemIconSpec() {
  wchar_t sys_dir[MAX_PATH];
  const UINT len = GetSystemDirectoryW(sys_dir, _countof(sys_dir));
  if (len == 0 || len >= _countof(sys_dir)) {
    return L"";
  }

  return std::wstring(sys_dir) + L"\\imageres.dll,-3";
}

std::wstring GetModulePath() {
  wchar_t path[MAX_PATH];
  path[0] = 0;
  if (g_instance) {
    GetModuleFileNameW(g_instance, path, _countof(path));
  } else {
    GetModuleFileNameW(nullptr, path, _countof(path));
  }
  return std::wstring(path);
}

std::wstring BuildModuleIconSpec(int resource_id) {
  std::wstring module = GetModulePath();
  if (module.empty()) {
    return GetSystemIconSpec();
  }

  return module + L",-" + std::to_wstring(resource_id);
}

int GetIconResourceIdForVerb(const std::wstring& verb) {
  for (const auto& command : kMenuCommands) {
    if (verb == command.verb) return command.icon;
  }
  return IDI_VERTREE_VIEWTREE;
}

HRESULT DupToCoTaskMem(const std::wstring& value, LPWSTR* out) {
  if (!out) return E_POINTER;
  *out = nullptr;
  const size_t bytes = (value.size() + 1) * sizeof(wchar_t);
  void* mem = CoTaskMemAlloc(bytes);
  if (!mem) return E_OUTOFMEMORY;
  memcpy(mem, value.c_str(), bytes);
  *out = static_cast<LPWSTR>(mem);
  return S_OK;
}

bool LaunchAppWithArgs(const std::wstring& args) {
  std::wstring app = GetAppPath();
  SHELLEXECUTEINFOW sei = {};
  sei.cbSize = sizeof(sei);
  sei.fMask = SEE_MASK_NOCLOSEPROCESS;
  sei.lpFile = app.c_str();
  sei.lpParameters = args.c_str();
  sei.nShow = SW_SHOWNORMAL;
  if (!ShellExecuteExW(&sei)) {
    LogLine(L"LaunchAppWithArgs failed");
    return false;
  }
  if (sei.hProcess) {
    CloseHandle(sei.hProcess);
  }
  return true;
}

std::wstring BuildArgs(const std::wstring& verb, const std::wstring& path) {
  std::wstring quoted = L"\"" + path + L"\"";
  return std::wstring(verb) + L" " + quoted;
}

std::wstring GetFirstItemPath(IShellItemArray* items) {
  if (!items) return L"";
  IShellItem* item = nullptr;
  if (FAILED(items->GetItemAt(0, &item)) || !item) {
    LogLine(L"GetFirstItemPath: GetItemAt failed");
    return L"";
  }
  wchar_t* path = nullptr;
  std::wstring result;
  if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path) {
    result = path;
    CoTaskMemFree(path);
  }
  item->Release();
  if (result.empty()) {
    LogLine(L"GetFirstItemPath: empty path");
  }
  return result;
}

class ComObjectBase {
 public:
  ComObjectBase() { InterlockedIncrement(&g_module_lock); }
  ULONG AddRef() { return InterlockedIncrement(&ref_count_); }
  ULONG Release() {
    ULONG count = InterlockedDecrement(&ref_count_);
    if (count == 0) delete this;
    return count;
  }

 protected:
  virtual ~ComObjectBase() { InterlockedDecrement(&g_module_lock); }

 private:
  ULONG ref_count_ = 1;
};

class LeafCommand : public IExplorerCommand, public ComObjectBase {
 public:
  LeafCommand(const wchar_t* verb, std::wstring title)
      : verb_(verb ? verb : L""), title_(std::move(title)) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IExplorerCommand) {
      *ppv = static_cast<IExplorerCommand*>(this);
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override { return ComObjectBase::AddRef(); }
  ULONG STDMETHODCALLTYPE Release() override { return ComObjectBase::Release(); }

  HRESULT STDMETHODCALLTYPE GetTitle(IShellItemArray*, LPWSTR* name) override {
    LogLine(L"LeafCommand GetTitle");
    if (!name) return E_POINTER;
    *name = nullptr;
    const HRESULT hr = DupToCoTaskMem(title_, name);
    LogHr(L"LeafCommand GetTitle", hr);
    return hr;
  }

  HRESULT STDMETHODCALLTYPE GetIcon(IShellItemArray*, LPWSTR* icon) override {
    LogLine(L"LeafCommand GetIcon");
    if (!icon) return E_POINTER;
    *icon = nullptr;
    const std::wstring spec = BuildModuleIconSpec(GetIconResourceIdForVerb(verb_));
    const HRESULT hr = DupToCoTaskMem(spec, icon);
    LogHr(L"LeafCommand GetIcon", hr);
    return hr;
  }

  HRESULT STDMETHODCALLTYPE GetToolTip(IShellItemArray*, LPWSTR* tip) override {
    LogLine(L"LeafCommand GetToolTip");
    if (!tip) return E_POINTER;
    *tip = nullptr;
    const std::wstring value;
    const HRESULT hr = DupToCoTaskMem(value, tip);
    LogHr(L"LeafCommand GetToolTip", hr);
    return hr;
  }

  HRESULT STDMETHODCALLTYPE GetCanonicalName(GUID* guid) override {
    LogLine(L"LeafCommand GetCanonicalName");
    if (!guid) return E_POINTER;
    CLSID clsid;
    const HRESULT hr = CLSIDFromString(kClsid, &clsid);
    if (FAILED(hr)) {
      *guid = GUID_NULL;
      LogHr(L"LeafCommand GetCanonicalName CLSIDFromString", hr);
      return S_OK;
    }
    *guid = clsid;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE GetState(IShellItemArray*, BOOL, EXPCMDSTATE* state) override {
    LogLine(L"LeafCommand GetState");
    if (!state) return E_POINTER;
    const bool enabled = IsWin11MenuEnabled();
    *state = enabled ? ECS_ENABLED : ECS_HIDDEN;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE Invoke(IShellItemArray* items, IBindCtx*) override {
    LogLine(L"LeafCommand Invoke");
    if (!items) return E_FAIL;
    std::wstring path = GetFirstItemPath(items);
    if (path.empty()) return E_FAIL;
    std::wstring args = BuildArgs(verb_, path);
    const bool ok = LaunchAppWithArgs(args);
    LogLine(ok ? L"LeafCommand Invoke ok" : L"LeafCommand Invoke failed");
    return ok ? S_OK : E_FAIL;
  }

  HRESULT STDMETHODCALLTYPE GetFlags(EXPCMDFLAGS* flags) override {
    LogLine(L"LeafCommand GetFlags");
    if (!flags) return E_POINTER;
    *flags = ECF_DEFAULT;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE EnumSubCommands(IEnumExplorerCommand** enum_commands) override {
    if (!enum_commands) return E_POINTER;
    *enum_commands = nullptr;
    return S_FALSE;
  }

 private:
  std::wstring verb_;
  std::wstring title_;
};

class CommandEnumerator : public IEnumExplorerCommand, public ComObjectBase {
 public:
  explicit CommandEnumerator(std::vector<IExplorerCommand*> commands, ULONG start = 0)
      : commands_(std::move(commands)), index_(start) {}

  ~CommandEnumerator() override {
    for (auto* cmd : commands_) {
      if (cmd) cmd->Release();
    }
  }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IEnumExplorerCommand) {
      *ppv = static_cast<IEnumExplorerCommand*>(this);
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override { return ComObjectBase::AddRef(); }
  ULONG STDMETHODCALLTYPE Release() override { return ComObjectBase::Release(); }

  HRESULT STDMETHODCALLTYPE Next(ULONG celt, IExplorerCommand** pUICommand,
                                 ULONG* pceltFetched) override {
    if (!pUICommand) return E_POINTER;
    if (!pceltFetched && celt != 1) return E_POINTER;
    if (pceltFetched) *pceltFetched = 0;

    ULONG fetched = 0;
    while (fetched < celt && index_ < commands_.size()) {
      IExplorerCommand* cmd = commands_[index_++];
      if (!cmd) continue;
      cmd->AddRef();
      pUICommand[fetched++] = cmd;
    }

    if (pceltFetched) *pceltFetched = fetched;
    return (fetched == celt) ? S_OK : S_FALSE;
  }

  HRESULT STDMETHODCALLTYPE Skip(ULONG celt) override {
    const ULONG remaining = static_cast<ULONG>(commands_.size() - index_);
    if (celt > remaining) {
      index_ = static_cast<ULONG>(commands_.size());
      return S_FALSE;
    }
    index_ += celt;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE Reset(void) override {
    index_ = 0;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE Clone(IEnumExplorerCommand** ppenum) override {
    if (!ppenum) return E_POINTER;
    *ppenum = nullptr;
    std::vector<IExplorerCommand*> cloned;
    cloned.reserve(commands_.size());
    for (auto* cmd : commands_) {
      if (!cmd) continue;
      cmd->AddRef();
      cloned.push_back(cmd);
    }
    auto* e = new CommandEnumerator(std::move(cloned), index_);
    *ppenum = e;
    return S_OK;
  }

 private:
  std::vector<IExplorerCommand*> commands_;
  ULONG index_ = 0;
};

class RootCommand : public IExplorerCommand, public ComObjectBase {
 public:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IExplorerCommand) {
      *ppv = static_cast<IExplorerCommand*>(this);
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override { return ComObjectBase::AddRef(); }
  ULONG STDMETHODCALLTYPE Release() override { return ComObjectBase::Release(); }

  HRESULT STDMETHODCALLTYPE GetTitle(IShellItemArray*, LPWSTR* name) override {
    LogLine(L"RootCommand GetTitle");
    if (!name) return E_POINTER;
    *name = nullptr;
    const HRESULT hr = DupToCoTaskMem(kMenuTitle, name);
    wchar_t buf[160];
    _snwprintf_s(buf, _countof(buf), _TRUNCATE,
                 L"RootCommand GetTitle hr=0x%08X out=%p", hr,
                 (name && *name) ? *name : nullptr);
    LogLine(buf);
    return hr;
  }

  HRESULT STDMETHODCALLTYPE GetIcon(IShellItemArray*, LPWSTR* icon) override {
    LogLine(L"RootCommand GetIcon");
    if (!icon) return E_POINTER;
    *icon = nullptr;
    const std::wstring spec = BuildModuleIconSpec(IDI_VERTREE_ROOT);
    const HRESULT hr = DupToCoTaskMem(spec, icon);
    LogHr(L"RootCommand GetIcon", hr);
    return hr;
  }

  HRESULT STDMETHODCALLTYPE GetToolTip(IShellItemArray*, LPWSTR* tip) override {
    LogLine(L"RootCommand GetToolTip");
    if (!tip) return E_POINTER;
    *tip = nullptr;

    const std::wstring value;
    const HRESULT hr = DupToCoTaskMem(value, tip);
    LogHr(L"RootCommand GetToolTip", hr);
    return hr;
  }

  HRESULT STDMETHODCALLTYPE GetCanonicalName(GUID* guid) override {
    LogLine(L"RootCommand GetCanonicalName");
    if (!guid) return E_POINTER;
    CLSID clsid;
    const HRESULT hr = CLSIDFromString(kClsid, &clsid);
    if (FAILED(hr)) {
      *guid = GUID_NULL;
      LogHr(L"RootCommand GetCanonicalName CLSIDFromString", hr);
      return S_OK;
    }
    *guid = clsid;
    LogLine(L"RootCommand GetCanonicalName ok");
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE GetState(IShellItemArray*, BOOL, EXPCMDSTATE* state) override {
    LogLine(L"RootCommand GetState");
    if (!state) return E_POINTER;
    const bool enabled = IsWin11MenuEnabled();
    *state = enabled ? ECS_ENABLED : ECS_HIDDEN;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE Invoke(IShellItemArray*, IBindCtx*) override {

    LogLine(L"RootCommand Invoke (ignored)");
    return E_NOTIMPL;
  }

  HRESULT STDMETHODCALLTYPE GetFlags(EXPCMDFLAGS* flags) override {
    LogLine(L"RootCommand GetFlags");
    if (!flags) return E_POINTER;
    *flags = ECF_HASSUBCOMMANDS;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE EnumSubCommands(IEnumExplorerCommand** enum_commands) override {
    LogLine(L"RootCommand EnumSubCommands");
    if (!enum_commands) return E_POINTER;
    *enum_commands = nullptr;

    std::vector<IExplorerCommand*> cmds;
    cmds.reserve(_countof(kMenuCommands));
    for (const auto& command : kMenuCommands) {
      cmds.push_back(new LeafCommand(command.verb, GetCommandTitle(command.verb)));
    }

    *enum_commands = new CommandEnumerator(std::move(cmds), 0);
    return S_OK;
  }
};

class ClassFactory : public IClassFactory, public ComObjectBase {
 public:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IClassFactory) {
      *ppv = static_cast<IClassFactory*>(this);
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override { return ComObjectBase::AddRef(); }
  ULONG STDMETHODCALLTYPE Release() override { return ComObjectBase::Release(); }

  HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID riid, void** ppv) override {
    if (outer) return CLASS_E_NOAGGREGATION;
    LogLine(L"CreateInstance RootCommand");
    auto* root = new RootCommand();
    HRESULT hr = root->QueryInterface(riid, ppv);
    root->Release();
    return hr;
  }

  HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override {
    if (lock) {
      InterlockedIncrement(&g_module_lock);
    } else {
      InterlockedDecrement(&g_module_lock);
    }
    return S_OK;
  }
};

}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_instance = module;
    DisableThreadLibraryCalls(module);
    wchar_t exe[MAX_PATH];
    exe[0] = 0;
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    wchar_t dll[MAX_PATH];
    dll[0] = 0;
    GetModuleFileNameW(module, dll, MAX_PATH);
    wchar_t buf[512];
    _snwprintf_s(buf, _countof(buf), _TRUNCATE, L"DllMain attach exe=%s dll=%s", exe, dll);
    LogLine(buf);
    LogLine(std::wstring(L"Config path: ") + GetConfigPath());
    LogFileLastWriteTime(L"DLL last write", dll);
  }
  return TRUE;
}

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv) {
  if (!ppv) return E_POINTER;
  *ppv = nullptr;

  CLSID clsid;
  if (FAILED(CLSIDFromString(kClsid, &clsid))) {
    LogLine(L"DllGetClassObject: CLSIDFromString failed");
    return CLASS_E_CLASSNOTAVAILABLE;
  }
  if (!IsEqualCLSID(rclsid, clsid)) {
    LogLine(L"DllGetClassObject: CLSID mismatch");
    return CLASS_E_CLASSNOTAVAILABLE;
  }

  wchar_t clsid_str[64];
  wchar_t riid_str[64];
  clsid_str[0] = 0;
  riid_str[0] = 0;
  StringFromGUID2(rclsid, clsid_str, _countof(clsid_str));
  StringFromGUID2(riid, riid_str, _countof(riid_str));
  wchar_t buf[256];
  _snwprintf_s(buf, _countof(buf), _TRUNCATE, L"DllGetClassObject rclsid=%s riid=%s", clsid_str, riid_str);
  LogLine(buf);
  LogLine(L"DllGetClassObject: create factory");
  auto* factory = new ClassFactory();
  HRESULT hr = factory->QueryInterface(riid, ppv);
  factory->Release();
  wchar_t buf2[128];
  _snwprintf_s(buf2, _countof(buf2), _TRUNCATE, L"DllGetClassObject QI hr=0x%08X", hr);
  LogLine(buf2);
  return hr;
}

STDAPI DllCanUnloadNow(void) {
  return (g_module_lock == 0) ? S_OK : S_FALSE;
}
