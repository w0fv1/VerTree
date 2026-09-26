#include "common.h"
#include <cwchar>
#include <iomanip>
#include <sstream>

namespace vt {
std::wstring wide(const std::string& value) {
  if (value.empty()) return {};
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
    static_cast<int>(value.size()), nullptr, 0);
  if (!size) throw Error("INVALID_UTF8", ERROR_NO_UNICODE_TRANSLATION, "Invalid UTF-8 path");
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
    static_cast<int>(value.size()), result.data(), size);
  return result;
}
std::string utf8(const std::wstring& value) {
  if (value.empty()) return {};
  int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
    static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (!size) throw Error("INVALID_UTF16", ERROR_NO_UNICODE_TRANSLATION, "Unpaired UTF-16 surrogate is not supported");
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
    static_cast<int>(value.size()), result.data(), size, nullptr, nullptr);
  return result;
}
std::string hex64(uint64_t value) {
  std::ostringstream out; out << std::hex << std::setfill('0') << std::setw(16) << value;
  return out.str();
}
std::string errorCode(DWORD value) {
  switch (value) {
    case ERROR_FILE_NOT_FOUND: case ERROR_PATH_NOT_FOUND: return "NOT_FOUND";
    case ERROR_SHARING_VIOLATION: case ERROR_LOCK_VIOLATION: return "SHARING_VIOLATION";
    case ERROR_ACCESS_DENIED: return "ACCESS_DENIED";
    case ERROR_DIR_NOT_EMPTY: return "DIRECTORY_NOT_EMPTY";
    case ERROR_WRITE_PROTECT: return "WRITE_PROTECTED";
    case ERROR_OPERATION_ABORTED: return "CANCELLED";
    case ERROR_NOT_READY: case ERROR_BAD_NETPATH: case ERROR_NETNAME_DELETED:
    case ERROR_DEVICE_NOT_CONNECTED: return "DEVICE_UNAVAILABLE";
    case ERROR_NOT_SUPPORTED: case ERROR_INVALID_FUNCTION: return "UNSUPPORTED_FILESYSTEM";
    case ERROR_DELETE_PENDING: return "DELETE_PENDING";
    default: return "IO_ERROR";
  }
}
std::string errorMessage(DWORD value) {
  wchar_t* buffer = nullptr;
  auto length = FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
    FORMAT_MESSAGE_IGNORE_INSERTS, nullptr, value, 0, reinterpret_cast<wchar_t*>(&buffer), 0, nullptr);
  std::wstring message = length && buffer ? std::wstring(buffer, length) : L"Windows error";
  if (buffer) LocalFree(buffer);
  while (!message.empty() && (message.back() == L'\r' || message.back() == L'\n')) message.pop_back();
  return utf8(message);
}
[[noreturn]] void failWin32(const char* operation, DWORD error) {
  throw Error(errorCode(error), error, std::string(operation) + ": " + errorMessage(error));
}
std::wstring executablePath() {
  std::wstring value(32768, L'\0');
  auto size = GetModuleFileNameW(nullptr, value.data(), static_cast<DWORD>(value.size()));
  if (!size || size >= value.size()) failWin32("GetModuleFileNameW");
  value.resize(size); return value;
}
std::wstring environment(const wchar_t* name) {
  auto size = GetEnvironmentVariableW(name, nullptr, 0);
  if (!size) return {};
  std::wstring value(size, L'\0');
  auto used = GetEnvironmentVariableW(name, value.data(), size);
  if (used >= size) return {};
  value.resize(used); return value;
}
bool samePath(const std::wstring& a, const std::wstring& b) {
  return CompareStringOrdinal(a.data(), static_cast<int>(a.size()), b.data(),
    static_cast<int>(b.size()), TRUE) == CSTR_EQUAL;
}
bool pathContains(const std::wstring& parent, const std::wstring& child) {
  if (samePath(parent, child)) return true;
  if (parent.empty() || child.size() <= parent.size()) return false;
  if (CompareStringOrdinal(parent.data(), static_cast<int>(parent.size()), child.data(),
    static_cast<int>(parent.size()), TRUE) != CSTR_EQUAL) return false;
  return parent.back() == L'\\' || child[parent.size()] == L'\\';
}
std::string processBirth(HANDLE process) {
  FILETIME created{}, exited{}, kernel{}, user{};
  if (!GetProcessTimes(process, &created, &exited, &kernel, &user)) failWin32("GetProcessTimes");
  return hex64((uint64_t(created.dwHighDateTime) << 32) | created.dwLowDateTime);
}
Json errorJson(const Error& error) {
  return {{"code", error.code}, {"win32", error.native}, {"message", error.what()}};
}
void Output::emit(Json value) {
  std::lock_guard<std::mutex> lock(mutex_);
  value["v"] = 1; value["sequence"] = ++sequence_;
  auto text = value.dump(-1, ' ', false, Json::error_handler_t::replace) + "\n";
  if (text.size() > kMaxRequestBytes) throw Error("PROTOCOL_LIMIT", 0, "Output frame is too large");
  size_t offset = 0;
  while (offset < text.size()) {
    DWORD written = 0;
    if (!WriteFile(handle_, text.data() + offset, static_cast<DWORD>(text.size() - offset), &written, nullptr)
        || written == 0) throw Error("HOST_DISCONNECTED", GetLastError(), "The controlling process disconnected");
    offset += written;
  }
}
bool Lines::read(std::string& line, size_t limit) {
  while (true) {
    auto end = buffered_.find('\n');
    if (end != std::string::npos) {
      line = buffered_.substr(0, end); buffered_.erase(0, end + 1);
      if (line.size() > limit) throw Error("PROTOCOL_LIMIT", 0, "Input frame is too large");
      if (!line.empty() && line.back() == '\r') line.pop_back();
      return true;
    }
    if (buffered_.size() > limit) throw Error("PROTOCOL_LIMIT", 0, "Input frame is too large");
    char data[8192]; DWORD bytes = 0;
    if (!ReadFile(handle_, data, sizeof(data), &bytes, nullptr) || !bytes) {
      if (!buffered_.empty()) throw Error("PROTOCOL_TRUNCATED", 0, "Input ended in the middle of a record");
      return false;
    }
    buffered_.append(data, bytes);
  }
}
bool Control::ready() const {
  while (paused.load() && !cancelled.load()) Sleep(25);
  return !cancelled.load();
}
void Control::command(const Json& value) {
  auto action = value.value("control", "");
  if (action == "cancel") { cancelled = true; paused = false; }
  else if (action == "pause" && !cancelled) paused = true;
  else if (action == "resume") paused = false;
}
NtApi::NtApi() {
  auto module = GetModuleHandleW(L"ntdll.dll");
  create = reinterpret_cast<NtCreateFileFn>(GetProcAddress(module, "NtCreateFile"));
  system = reinterpret_cast<NtQuerySystemInformationFn>(GetProcAddress(module, "NtQuerySystemInformation"));
  object = reinterpret_cast<NtQueryObjectFn>(GetProcAddress(module, "NtQueryObject"));
  toDos = reinterpret_cast<RtlNtStatusToDosErrorFn>(GetProcAddress(module, "RtlNtStatusToDosError"));
  if (!create || !system || !object || !toDos) throw Error("NATIVE_API_UNAVAILABLE", 0, "Required Windows API unavailable");
}
NtApi& nt() { static NtApi api; return api; }
Handle openRelative(HANDLE parent, const std::wstring& name, ACCESS_MASK access, bool pin, bool exactCase) {
  if (name.empty() || name == L"." || name == L".." || name.find_first_of(L"\\/:") != std::wstring::npos
      || name.find(L'\0') != std::wstring::npos || name.size() > 32760)
    throw Error("UNSAFE_COMPONENT", 0, "Invalid relative path component");
  UNICODE_STRING objectName{};
  objectName.Buffer = const_cast<PWSTR>(name.data());
  objectName.Length = static_cast<USHORT>(name.size() * sizeof(wchar_t));
  objectName.MaximumLength = objectName.Length;
  OBJECT_ATTRIBUTES object{}; object.Length = sizeof(object); object.RootDirectory = parent;
  object.ObjectName = &objectName; object.Attributes = exactCase ? 0 : 0x40;
  IO_STATUS_BLOCK io{}; HANDLE result = nullptr;
  // FILE_OPEN, FILE_SYNCHRONOUS_IO_NONALERT, FILE_OPEN_REPARSE_POINT.
  auto status = nt().create(&result, access | SYNCHRONIZE, &object, &io, nullptr, 0,
    FILE_SHARE_READ | FILE_SHARE_WRITE | (pin ? 0 : FILE_SHARE_DELETE), 1,
    0x00000020 | 0x00200000, nullptr, 0);
  if (status < 0) failWin32("NtCreateFile(relative)", nt().toDos(status));
  return Handle(result);
}
}
