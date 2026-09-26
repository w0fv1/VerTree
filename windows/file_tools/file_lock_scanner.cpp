#include "file_lock_scanner.h"
#include "identity_bound_scan.h"
#include <psapi.h>
#include <tlhelp32.h>
#include <sddl.h>
#include <array>
#include <map>
#include <set>

namespace vt {
namespace {
struct SystemHandleEntry {
  PVOID object; ULONG_PTR pid, value; ULONG access;
  USHORT backTrace, typeIndex; ULONG attributes, reserved;
};
struct SystemHandles { ULONG_PTR count, reserved; SystemHandleEntry entries[1]; };
struct Target {
  std::wstring display, kernelPath;
  bool directory = false;
  FILE_ID_INFO id{};
  bool hasId = false;
};
std::wstring handleName(HANDLE handle) {
  std::wstring value(1024, L'\0');
  DWORD count = GetFinalPathNameByHandleW(handle, value.data(), static_cast<DWORD>(value.size()), VOLUME_NAME_NT);
  if (count >= value.size() && count <= 32768) {
    value.resize(count + 1);
    count = GetFinalPathNameByHandleW(handle, value.data(), static_cast<DWORD>(value.size()), VOLUME_NAME_NT);
  }
  if (!count || count >= value.size()) return {};
  value.resize(count); return value;
}
std::vector<BYTE> systemHandles() {
  std::vector<BYTE> data(1024 * 1024);
  while (data.size() <= 64 * 1024 * 1024) {
    ULONG needed = 0;
    auto status = nt().system(64, data.data(), static_cast<ULONG>(data.size()), &needed);
    if (static_cast<ULONG>(status) == 0xC0000004) {
      auto next = std::max(data.size() * 2, static_cast<size_t>(needed) + 65536);
      if (next > 64 * 1024 * 1024) break;
      data.resize(next); continue;
    }
    if (status < 0) failWin32("SystemExtendedHandleInformation", nt().toDos(status));
    const auto* info = reinterpret_cast<const SystemHandles*>(data.data());
    if (info->count > (data.size() - offsetof(SystemHandles, entries)) / sizeof(SystemHandleEntry))
      throw Error("INVALID_HANDLE_SNAPSHOT", 0, "Windows returned an invalid handle snapshot");
    return data;
  }
  throw Error("SCAN_LIMIT", 0, "The system handle table exceeds the bounded scan budget");
}
std::vector<DWORD> processIds() {
  Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
  if (!snapshot) failWin32("Process snapshot");
  PROCESSENTRY32W entry{}; entry.dwSize = sizeof(entry);
  std::vector<DWORD> result;
  if (Process32FirstW(snapshot.get(), &entry)) do {
    if (result.size() >= 65536) throw Error("SCAN_LIMIT", 0, "Too many processes");
    result.push_back(entry.th32ProcessID);
  } while (Process32NextW(snapshot.get(), &entry));
  return result;
}
std::wstring accountName(HANDLE process) {
  Handle token; HANDLE raw = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &raw)) return {};
  token.reset(raw); DWORD size = 0;
  GetTokenInformation(token.get(), TokenUser, nullptr, 0, &size);
  if (size == 0 || size > 65536) return {};
  std::vector<BYTE> bytes(size);
  if (!GetTokenInformation(token.get(), TokenUser, bytes.data(), size, &size)) return {};
  auto user = reinterpret_cast<TOKEN_USER*>(bytes.data());
  wchar_t name[256]{}, domain[256]{}; DWORD nameSize = 256, domainSize = 256; SID_NAME_USE use{};
  if (!LookupAccountSidW(nullptr, user->User.Sid, name, &nameSize, domain, &domainSize, &use)) return {};
  return std::wstring(domain) + L"\\" + name;
}
}
std::wstring processImage(HANDLE process) {
  std::wstring path(32768, L'\0'); DWORD size = static_cast<DWORD>(path.size());
  if (!QueryFullProcessImageNameW(process, 0, path.data(), &size)) return {};
  path.resize(size); return path;
}
std::string processActionRestriction(HANDLE process, DWORD pid, DWORD hostPid) {
  if (pid <= 4 || pid == GetCurrentProcessId() || pid == hostPid) return "SYSTEM_OR_SELF";
  DWORD session = 0;
  if (!ProcessIdToSessionId(pid, &session) || session == 0) return "SERVICE_OR_UNKNOWN_SESSION";
  BOOL critical = FALSE;
  if (!IsProcessCritical(process, &critical)) return "PROTECTION_UNKNOWN";
  if (critical) return "CRITICAL_PROCESS";
  PROCESS_PROTECTION_LEVEL_INFORMATION protection{};
  if (!GetProcessInformation(process, ProcessProtectionLevelInfo, &protection, sizeof(protection)))
    return "PROTECTION_UNKNOWN";
  if (protection.ProtectionLevel != PROTECTION_LEVEL_NONE) return "PROTECTED_PROCESS";
  if (processImage(process).empty()) return "IDENTITY_UNKNOWN";
  return {};
}
Json describeProcess(DWORD pid, DWORD hostPid) {
  Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid));
  Json result{{"pid", pid}, {"creationTime", ""}, {"name", "PID " + std::to_string(pid)},
    {"imagePath", ""}, {"user", ""}, {"actionAllowed", false}, {"restriction", "ACCESS_DENIED"}};
  if (!process) return result;
  try { result["creationTime"] = processBirth(process.get()); } catch (const Error&) { return result; }
  auto image = processImage(process.get());
  result["imagePath"] = utf8(image);
  result["name"] = image.empty() ? "PID " + std::to_string(pid) : utf8(image.substr(image.find_last_of(L'\\') + 1));
  result["user"] = utf8(accountName(process.get()));
  auto restriction = processActionRestriction(process.get(), pid, hostPid);
  result["restriction"] = restriction; result["actionAllowed"] = restriction.empty();
  return result;
}
Json scanFileUsage(const Json& request, Control& control, Output& output) {
  const auto& paths = request.at("paths");
  if (!paths.is_array() || paths.empty() || paths.size() > kMaxTargets)
    throw Error("SELECTION_LIMIT", 0, "Select 1 to 1024 paths");
  const DWORD onlyPid = request.value("onlyPid", DWORD(0));
  const DWORD hostPid = request.value("hostPid", DWORD(0));
  const auto started = Clock::now();
  auto lastProgress = started;
  const int budget = std::clamp(request.value("budgetSeconds", 45), 1, 60);
  std::vector<Target> targets;
  std::vector<Handle> targetHandles;
  std::vector<Binding> pinnedTargets;
  size_t targetIndex = 0;
  Json warnings = Json::array();
  bool incomplete = false;
  for (const auto& item : paths) {
    Target target; target.display = normalizedPath(wide(item.get<std::string>()));
    Handle handle;
    const auto index = targetIndex++;
    try { handle = openUsageTarget(request, target.display, index, pinnedTargets); }
    catch (const Error& error) {
      incomplete = true;
      warnings.push_back({{"path", utf8(target.display)}, {"code", error.code}});
      continue;
    }
    if (!handle) {
      const auto code = GetLastError(); incomplete = true;
      warnings.push_back({{"path", utf8(target.display)}, {"code", errorCode(code)}, {"win32", code}});
      continue;
    }
    FILE_STANDARD_INFO standard{};
    if (!GetFileInformationByHandleEx(handle.get(), FileStandardInfo, &standard, sizeof(standard))) {
      incomplete = true; continue;
    }
    target.directory = standard.Directory != FALSE && !request.value("exactPaths", false);
    target.kernelPath = handleName(handle.get());
    target.hasId = GetFileInformationByHandleEx(handle.get(), FileIdInfo, &target.id, sizeof(target.id)) != FALSE;
    if (target.kernelPath.empty()) { incomplete = true; continue; }
    targets.push_back(std::move(target)); targetHandles.push_back(std::move(handle));
  }
  if (targets.empty()) throw Error("SCAN_TARGET_UNAVAILABLE", 0, "No selected path could be inspected");
  auto snapshot = systemHandles();
  const auto* info = reinterpret_cast<SystemHandles*>(snapshot.data());
  USHORT fileType = 0;
  for (size_t index = 0; index < info->count; ++index) {
    const auto& entry = info->entries[index];
    if (entry.pid == GetCurrentProcessId() && entry.value == reinterpret_cast<ULONG_PTR>(targetHandles.front().get())) {
      fileType = entry.typeIndex; break;
    }
  }
  if (fileType == 0) throw Error("SCAN_TYPE_UNAVAILABLE", 0, "The file handle type could not be identified safely");
  std::map<DWORD, Handle> processHandles;
  std::set<DWORD> inaccessible;
  std::map<DWORD, Json> matches;
  size_t resultBytes = 0, checked = 0, deniedHandles = 0;
  auto addMatch = [&](DWORD pid, const std::wstring& path, const char* source) {
    if (pid == GetCurrentProcessId()) return;
    auto found = matches.find(pid);
    if (found == matches.end()) {
      if (matches.size() >= 2048) { incomplete = true; return; }
      auto process = describeProcess(pid, hostPid); process["files"] = Json::array();
      resultBytes += process.dump().size();
      found = matches.emplace(pid, std::move(process)).first;
    }
    auto& files = found->second["files"];
    const auto display = utf8(path);
    for (auto& file : files) if (file["path"] == display) {
      auto& sources = file["sources"];
      if (std::find(sources.begin(), sources.end(), source) == sources.end()) sources.push_back(source);
      return;
    }
    if (files.size() >= 256 || resultBytes + display.size() + 128 > 1024 * 1024) {
      incomplete = true; return;
    }
    files.push_back({{"path", display}, {"sources", Json::array({source})}});
    resultBytes += display.size() + 128;
    output.emit({{"type", "process"}, {"process", found->second}});
  };
  auto pathMatch = [&](const std::wstring& kernel) -> std::wstring {
    for (const auto& target : targets) {
      if (samePath(kernel, target.kernelPath)) return target.display;
      if (target.directory && pathContains(target.kernelPath, kernel))
        return target.display + kernel.substr(target.kernelPath.size());
    }
    return {};
  };
  auto step = [&](const char* phase) {
    if (!control.ready()) return false;
    const auto now = Clock::now();
    if (std::chrono::duration_cast<std::chrono::seconds>(now - started).count() >= budget) {
      incomplete = true; return false;
    }
    if (now - lastProgress >= std::chrono::milliseconds(200)) {
      output.emit({{"type", "scanProgress"}, {"phase", phase}, {"checkedHandles", checked},
        {"totalHandles", info->count}, {"inaccessibleProcesses", inaccessible.size()}});
      lastProgress = now;
    }
    return true;
  };
  output.emit({{"type", "scanProgress"}, {"phase", "handles"}, {"checkedHandles", 0}, {"totalHandles", info->count}});
  for (size_t index = 0; index < info->count; ++index) {
    const auto& entry = info->entries[index];
    if (entry.typeIndex != fileType || entry.pid > MAXDWORD || entry.pid == GetCurrentProcessId()) continue;
    const auto pid = static_cast<DWORD>(entry.pid);
    if (onlyPid && pid != onlyPid) continue;
    if (!step("handles")) break;
    ++checked;
    if (inaccessible.count(pid)) { ++deniedHandles; continue; }
    auto found = processHandles.find(pid);
    if (found == processHandles.end()) {
      if (processHandles.size() >= 8192) { incomplete = true; break; }
      Handle process(OpenProcess(PROCESS_DUP_HANDLE, FALSE, pid));
      if (!process) { inaccessible.insert(pid); ++deniedHandles; continue; }
      found = processHandles.emplace(pid, std::move(process)).first;
    }
    HANDLE raw = nullptr;
    if (!DuplicateHandle(found->second.get(), reinterpret_cast<HANDLE>(entry.value), GetCurrentProcess(),
        &raw, 0, FALSE, DUPLICATE_SAME_ACCESS)) { ++deniedHandles; continue; }
    Handle localCopy(raw);
    // Queries stay in this isolated helper; never force-close a foreign handle.
    if (GetFileType(localCopy.get()) != FILE_TYPE_DISK) continue;
    auto name = handleName(localCopy.get());
    auto path = pathMatch(name);
    if (!path.empty()) { addMatch(pid, path, "handle"); continue; }
    for (const auto& target : targets) {
      if (target.directory || !target.hasId) continue;
      FILE_ID_INFO id{};
      if (!GetFileInformationByHandleEx(localCopy.get(), FileIdInfo, &id, sizeof(id))) break;
      if (id.VolumeSerialNumber == target.id.VolumeSerialNumber &&
          std::memcmp(id.FileId.Identifier, target.id.FileId.Identifier, 16) == 0) {
        addMatch(pid, target.display, "handle:file-id"); break;
      }
    }
  }
  // Loaded executable images/DLLs may keep files in use without file handles.
  for (DWORD pid : processIds()) {
    if (pid == GetCurrentProcessId() || (onlyPid && pid != onlyPid)) continue;
    if (!step("modules")) break;
    Handle process(OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid));
    if (!process) { inaccessible.insert(pid); continue; }
    std::vector<HMODULE> modules(256); DWORD bytes = 0;
    if (!EnumProcessModulesEx(process.get(), modules.data(), static_cast<DWORD>(modules.size() * sizeof(HMODULE)),
        &bytes, LIST_MODULES_ALL)) { inaccessible.insert(pid); continue; }
    if (bytes / sizeof(HMODULE) > 16384) { incomplete = true; continue; }
    if (bytes > modules.size() * sizeof(HMODULE)) {
      modules.resize(bytes / sizeof(HMODULE));
      if (!EnumProcessModulesEx(process.get(), modules.data(), bytes, &bytes, LIST_MODULES_ALL)) continue;
    }
    const size_t count = std::min(modules.size(), bytes / sizeof(HMODULE));
    for (size_t index = 0; index < count; ++index) {
      if (!step("modules")) break;
      std::wstring kernel(32768, L'\0');
      auto size = GetMappedFileNameW(process.get(), modules[index], kernel.data(), static_cast<DWORD>(kernel.size()));
      if (!size || size >= kernel.size()) continue;
      kernel.resize(size); auto path = pathMatch(kernel);
      if (!path.empty()) addMatch(pid, path, "module");
    }
  }
  incomplete |= !inaccessible.empty() || deniedHandles != 0 || control.cancelled.load();
  Json processes = Json::array();
  for (auto& pair : matches) processes.push_back(std::move(pair.second));
  return {{"processes", processes}, {"complete", !incomplete}, {"warnings", warnings},
    {"cancelled", control.cancelled.load()}, {"checkedHandles", checked},
    {"inaccessibleProcesses", inaccessible.size()}, {"uninspectedHandles", deniedHandles},
    {"scope", "local-machine"}, {"elapsedSeconds", std::chrono::duration<double>(Clock::now() - started).count()}};
}
}
