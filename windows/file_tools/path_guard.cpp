#include "path_guard.h"
#include <winioctl.h>
#include <cstring>
#include <sstream>
#include <iomanip>

namespace vt {
std::string identityOf(uint64_t volume, const BYTE* id, uint64_t created) {
  std::ostringstream out; out << hex64(volume) << ':';
  for (size_t i = 0; i < 16; ++i) out << std::hex << std::setfill('0') << std::setw(2) << unsigned(id[i]);
  out << ':' << hex64(created); return out.str();
}
FileMeta metadata(HANDLE handle) {
  FILE_ID_INFO id{}; FILE_BASIC_INFO basic{}; FILE_STANDARD_INFO standard{}; FILE_ATTRIBUTE_TAG_INFO tag{};
  if (!GetFileInformationByHandleEx(handle, FileIdInfo, &id, sizeof(id))) failWin32("FileIdInfo");
  if (!GetFileInformationByHandleEx(handle, FileBasicInfo, &basic, sizeof(basic))) failWin32("FileBasicInfo");
  if (!GetFileInformationByHandleEx(handle, FileStandardInfo, &standard, sizeof(standard))) failWin32("FileStandardInfo");
  if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfo, &tag, sizeof(tag))) failWin32("FileAttributeTagInfo");
  bool nonzero = false; for (auto byte : id.FileId.Identifier) nonzero |= byte != 0;
  if (!nonzero) throw Error("UNSUPPORTED_IDENTITY", 0, "Filesystem returned an unusable file ID");
  return {identityOf(id.VolumeSerialNumber, id.FileId.Identifier, basic.CreationTime.QuadPart),
    hex64(id.VolumeSerialNumber), basic.FileAttributes, tag.ReparseTag,
    static_cast<uint64_t>(standard.EndOfFile.QuadPart)};
}
std::wstring extendedPath(const std::wstring& input) {
  return input.rfind(L"\\\\", 0) == 0 ? L"\\\\?\\UNC\\" + input.substr(2) : L"\\\\?\\" + input;
}
std::wstring canonicalHandlePath(HANDLE handle) {
  std::wstring value(32768, L'\0');
  const auto count = GetFinalPathNameByHandleW(handle, value.data(), static_cast<DWORD>(value.size()), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  if (!count || count >= value.size()) failWin32("Canonical object path");
  value.resize(count); return normalizedPath(value);
}
std::wstring normalizedPath(const std::wstring& input) {
  if (input.empty() || input.size() > 32750 || input.find(L'\0') != std::wstring::npos)
    throw Error("INVALID_PATH", 0, "An absolute filesystem path is required");
  std::wstring path = input;
  std::replace(path.begin(), path.end(), L'/', L'\\');
  if (path.rfind(L"\\\\?\\UNC\\", 0) == 0) path = L"\\\\" + path.substr(8);
  else if (path.rfind(L"\\\\?\\", 0) == 0) path = path.substr(4);
  if (path.rfind(L"\\\\.\\", 0) == 0 || path.rfind(L"\\??\\", 0) == 0 ||
      path.find_first_of(L"*?\"") != std::wstring::npos)
    throw Error("INVALID_PATH", 0, "Device namespaces and wildcard paths are not supported");
  bool drive = path.size() >= 3 && ((path[0] >= L'A' && path[0] <= L'Z') || (path[0] >= L'a' && path[0] <= L'z'))
    && path[1] == L':' && path[2] == L'\\';
  bool unc = path.rfind(L"\\\\", 0) == 0;
  if (!drive && !unc) throw Error("INVALID_PATH", 0, "Relative and drive-relative paths are not allowed");
  if (path.find(L':', drive ? 2 : 0) != std::wstring::npos)
    throw Error("INVALID_PATH", 0, "Alternate data stream paths are not allowed");
  size_t start = drive ? 3 : 2;
  while (start < path.size()) {
    auto end = path.find(L'\\', start); if (end == std::wstring::npos) end = path.size();
    auto part = path.substr(start, end - start);
    if (part.empty() || part == L"." || part == L".." || part.back() == L'.' || part.back() == L' ')
      throw Error("AMBIGUOUS_PATH", 0, "Dot components, repeated separators, and trailing dots/spaces are not supported");
    start = end + 1;
  }
  while (path.size() > 3 && path.back() == L'\\') path.pop_back();
  return path;
}
static size_t rootLength(const std::wstring& path) {
  if (path.size() >= 3 && path[1] == L':') return 3;
  auto server = path.find(L'\\', 2);
  auto share = server == std::wstring::npos ? server : path.find(L'\\', server + 1);
  if (server == std::wstring::npos || server + 1 >= path.size() || share == std::wstring::npos)
    throw Error("PROTECTED_ROOT", 0, "A UNC server/share root cannot be deleted");
  return share + 1;
}
void validateDeletePath(const std::wstring& path, const Json& extraProtected) {
  if (path.size() <= rootLength(path)) throw Error("PROTECTED_ROOT", 0, "Volume and share roots cannot be deleted");
  wchar_t windows[32768]{}; GetWindowsDirectoryW(windows, 32768);
  std::vector<std::wstring> protectedTrees{windows, environment(L"ProgramFiles"),
    environment(L"ProgramFiles(x86)"), environment(L"ProgramData")};
  const auto executable = executablePath();
  protectedTrees.push_back(executable.substr(0, executable.find_last_of(L'\\')));
  if (extraProtected.is_array()) {
    for (const auto& item : extraProtected) protectedTrees.push_back(normalizedPath(wide(item.get<std::string>())));
  }
  for (const auto& root : protectedTrees) {
    if (!root.empty() && (pathContains(root, path) || pathContains(path, root)))
      throw Error("PROTECTED_PATH", 0, "The selection intersects a protected system/application directory");
  }
  const auto home = environment(L"USERPROFILE");
  if (!home.empty() && pathContains(path, home))
    throw Error("PROTECTED_ROOT", 0, "The user-profile root cannot be deleted");
}
void validateReparse(HANDLE handle, const FileMeta& meta) {
  if (!meta.reparse()) return;
  if (meta.tag == IO_REPARSE_TAG_SYMLINK) return;
  if (meta.tag == IO_REPARSE_TAG_MOUNT_POINT) {
    std::vector<BYTE> data(MAXIMUM_REPARSE_DATA_BUFFER_SIZE); DWORD count = 0;
    if (!DeviceIoControl(handle, FSCTL_GET_REPARSE_POINT, nullptr, 0, data.data(),
        static_cast<DWORD>(data.size()), &count, nullptr)) failWin32("FSCTL_GET_REPARSE_POINT");
    if (count < 16) throw Error("UNSUPPORTED_REPARSE", 0, "Invalid reparse data");
    WORD offset = 0, length = 0;
    std::memcpy(&offset, data.data() + 8, 2); std::memcpy(&length, data.data() + 10, 2);
    if ((length & 1) || 16u + offset + length > count)
      throw Error("UNSUPPORTED_REPARSE", 0, "Invalid junction data");
    std::wstring substitute(reinterpret_cast<wchar_t*>(data.data() + 16 + offset), length / 2);
    if (substitute.rfind(L"\\??\\Volume{", 0) == 0)
      throw Error("VOLUME_MOUNT_POINT", 0, "Mounted volumes must be managed with Windows disk tools");
    return;
  }
  throw Error("UNSUPPORTED_REPARSE", 0, "Unknown/cloud reparse points are preserved; links are never traversed");
}
Binding bindPath(const std::wstring& input, bool mutate, const Json* expected, bool removeReadOnly) {
  Binding binding; binding.path = normalizedPath(input);
  const auto rootSize = rootLength(binding.path);
  auto root = extendedPath(binding.path.substr(0, rootSize));
  Handle current(CreateFileW(root.c_str(), FILE_READ_ATTRIBUTES | FILE_TRAVERSE | SYNCHRONIZE,
    FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  if (!current) failWin32("Open volume/share root");
  auto parentMeta = metadata(current.get());
  if (parentMeta.reparse()) throw Error("REPARSE_ANCESTOR", 0, "Reparse ancestors are not traversed");
  size_t start = rootSize;
  while (start < binding.path.size()) {
    auto end = binding.path.find(L'\\', start); bool last = end == std::wstring::npos;
    auto name = binding.path.substr(start, last ? std::wstring::npos : end - start);
    binding.ancestorIds.push_back(parentMeta.identity);
    if (expected) {
      const auto& ids = expected->at("ancestors");
      const auto index = binding.ancestorIds.size() - 1;
      if (!ids.is_array() || index >= ids.size() || ids[index] != parentMeta.identity)
        throw Error("TARGET_CHANGED", 0, "An ancestor was replaced after confirmation");
    }
    ACCESS_MASK access = FILE_READ_ATTRIBUTES;
    if (!last) access |= FILE_TRAVERSE;
    if (last && mutate) {
      access |= DELETE;
      if (expected && expected->value("directory", false) && expected->value("tag", 0u) == 0)
        access |= FILE_LIST_DIRECTORY;
      if (removeReadOnly && expected && (expected->value("attributes", 0u) & FILE_ATTRIBUTE_READONLY))
        access |= FILE_WRITE_ATTRIBUTES;
    }
    FILE_CASE_SENSITIVE_INFO caseInfo{};
    const bool caseSensitive = GetFileInformationByHandleEx(current.get(), FileCaseSensitiveInfo,
      &caseInfo, sizeof(caseInfo)) && (caseInfo.Flags & 1);
    auto next = openRelative(current.get(), name, access, true, caseSensitive);
    auto meta = metadata(next.get());
    binding.ancestors.push_back(std::move(current));
    if (!last) {
      if (!meta.directory() || meta.reparse())
        throw Error("REPARSE_ANCESTOR", 0, "Only ordinary directory ancestors are supported");
      current = std::move(next); parentMeta = meta; start = end + 1;
      if (binding.ancestors.size() > kMaxDepth)
        throw Error("DEPTH_LIMIT", 0, "Path exceeds the bounded traversal depth");
    } else {
      if (expected && (expected->at("identity") != meta.identity ||
          expected->at("ancestors").size() != binding.ancestorIds.size()))
        throw Error("TARGET_CHANGED", 0, "The selected object was replaced after confirmation");
      binding.target = std::move(next); binding.meta = meta; break;
    }
  }
  if (!binding.target) throw Error("PROTECTED_ROOT", 0, "A root directory cannot be a target");
  return binding;
}
static Handle volumeHandle(const std::wstring& path) {
  if (path.size() < 3 || path[1] != L':') return {};
  auto device = L"\\\\.\\" + path.substr(0, 2);
  return Handle(CreateFileW(device.c_str(), 0, FILE_SHARE_READ | FILE_SHARE_WRITE,
    nullptr, OPEN_EXISTING, 0, nullptr));
}
std::string deviceKey(const std::wstring& path) {
  if (path.rfind(L"\\\\", 0) == 0) {
    auto server = path.find(L'\\', 2); return "remote:" + utf8(path.substr(0, server));
  }
  auto volume = volumeHandle(path); STORAGE_DEVICE_NUMBER number{}; DWORD bytes = 0;
  if (volume && DeviceIoControl(volume.get(), IOCTL_STORAGE_GET_DEVICE_NUMBER, nullptr, 0,
      &number, sizeof(number), &bytes, nullptr)) return "disk:" + std::to_string(number.DeviceNumber);
  return "unknown-local";
}
int suggestedWorkers(const std::wstring& path) {
  if (path.rfind(L"\\\\", 0) == 0) return 2;
  auto volume = volumeHandle(path); if (!volume) return 1;
  STORAGE_PROPERTY_QUERY query{}; query.PropertyId = StorageDeviceSeekPenaltyProperty;
  query.QueryType = PropertyStandardQuery; DEVICE_SEEK_PENALTY_DESCRIPTOR result{}; DWORD bytes = 0;
  if (DeviceIoControl(volume.get(), IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query),
      &result, sizeof(result), &bytes, nullptr) && bytes >= sizeof(result)) return result.IncursSeekPenalty ? 1 : 4;
  return 1;
}
Json describeTarget(const Binding& binding) {
  return {{"path", utf8(binding.path)}, {"identity", binding.meta.identity},
    {"ancestors", binding.ancestorIds}, {"directory", binding.meta.directory()},
    {"attributes", binding.meta.attributes}, {"tag", binding.meta.tag},
    {"logicalSize", binding.meta.logicalSize}, {"deviceKey", deviceKey(binding.path)},
    {"suggestedWorkers", suggestedWorkers(binding.path)}};
}
Json prepareTargets(const Json& request) {
  const auto& paths = request.at("paths");
  if (!paths.is_array() || paths.empty() || paths.size() > kMaxTargets)
    throw Error("SELECTION_LIMIT", 0, "Select 1 to 1024 top-level filesystem items");
  Json targets = Json::array();
  for (const auto& item : paths) {
    auto path = normalizedPath(wide(item.get<std::string>()));
    validateDeletePath(path, request.value("protectedPaths", Json::array()));
    auto binding = bindPath(path, false); validateReparse(binding.target.get(), binding.meta);
    const auto canonical = canonicalHandlePath(binding.target.get());
    validateDeletePath(canonical, request.value("protectedPaths", Json::array()));
    if (!samePath(path, canonical)) {
      binding = Binding{}; // Release handles before rebinding the canonical spelling.
      path = canonical; binding = bindPath(path, false);
      validateReparse(binding.target.get(), binding.meta);
    }
    bool covered = false;
    for (const auto& old : targets) {
      auto previous = wide(old.at("path").get<std::string>());
      if (samePath(previous, path) || (old.value("directory", false) && !old.value("tag", 0u) &&
          pathContains(previous, path))) covered = true;
    }
    if (covered) continue;
    if (binding.meta.directory() && !binding.meta.reparse()) {
      targets.erase(std::remove_if(targets.begin(), targets.end(), [&](const Json& old) {
        return pathContains(path, wide(old.at("path").get<std::string>()));
      }), targets.end());
    }
    targets.push_back(describeTarget(binding));
  }
  return {{"targets", targets}};
}
}
