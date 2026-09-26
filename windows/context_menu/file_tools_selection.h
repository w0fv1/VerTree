#pragma once
#include <windows.h>
#include <shlobj.h>
#include <string>
#include <vector>

// Explorer performs only a bounded top-level handoff. No recursive enumeration,
// deletion, process enumeration, or termination runs inside the shell process.
namespace vertree_selection {
constexpr size_t kMaximumTargets = 1024;
constexpr size_t kMaximumBytes = 4 * 1024 * 1024;
constexpr wchar_t kUsageClsid[] = L"{D6F4258B-C42C-487A-ABCE-94A6BE01D6B1}";
constexpr wchar_t kDeleteClsid[] = L"{1C501413-5FC4-4E07-B132-790198D45724}";

inline bool IsToolVerb(const std::wstring& verb) {
  return verb == L"unlock" || verb == L"fast-delete";
}
inline bool SelectionSupported(IShellItemArray* items, bool tools) {
  if (!items) return false;
  DWORD count = 0;
  if (FAILED(items->GetCount(&count)) || !count || count > kMaximumTargets || (!tools && count != 1)) return false;
  SFGAOF attributes = 0;
  if (FAILED(items->GetAttributes(SIATTRIBFLAGS_AND, SFGAO_FILESYSTEM, &attributes)) ||
      !(attributes & SFGAO_FILESYSTEM)) return false;
  if (!tools) {
    attributes = 0;
    if (FAILED(items->GetAttributes(SIATTRIBFLAGS_OR, SFGAO_FOLDER, &attributes)) ||
        (attributes & SFGAO_FOLDER)) return false;
  }
  return true;
}
inline bool CollectPaths(IShellItemArray* items, std::vector<std::wstring>& paths) {
  if (!SelectionSupported(items, true)) return false;
  DWORD count = 0; if (FAILED(items->GetCount(&count))) return false;
  paths.clear(); paths.reserve(count);
  size_t characters = 0;
  for (DWORD index = 0; index < count; ++index) {
    IShellItem* item = nullptr;
    if (FAILED(items->GetItemAt(index, &item)) || !item) return false;
    PWSTR text = nullptr;
    const auto result = item->GetDisplayName(SIGDN_FILESYSPATH, &text);
    item->Release();
    if (FAILED(result) || !text) return false;
    std::wstring path(text); CoTaskMemFree(text);
    if (path.empty() || path.size() > 32750) return false;
    characters += path.size();
    if (characters > kMaximumBytes / 3) return false;
    paths.push_back(std::move(path));
  }
  return true;
}
inline std::wstring EscapeJson(const std::wstring& value) {
  constexpr wchar_t hex[] = L"0123456789abcdef";
  std::wstring result = L"\"";
  for (wchar_t character : value) {
    if (character == L'"' || character == L'\\') { result += L'\\'; result += character; }
    else if (character < 0x20) {
      result += L"\\u00";
      result += hex[(character >> 4) & 15]; result += hex[character & 15];
    } else result += character;
  }
  result += L'"'; return result;
}
inline bool EncodePaths(const std::vector<std::wstring>& paths, std::string& encoded) {
  if (paths.empty() || paths.size() > kMaximumTargets) return false;
  std::wstring json = L"{\"schemaVersion\":1,\"owner\":\"VerTree.Explorer\",\"paths\":[";
  for (size_t index = 0; index < paths.size(); ++index) {
    if (index) json += L',';
    json += EscapeJson(paths[index]);
    if (json.size() > kMaximumBytes) return false;
  }
  json += L"]}";
  const auto size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, json.data(),
    static_cast<int>(json.size()), nullptr, 0, nullptr, nullptr);
  if (size <= 0 || static_cast<size_t>(size) > kMaximumBytes) return false;
  encoded.resize(size);
  return WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, json.data(),
    static_cast<int>(json.size()), encoded.data(), size, nullptr, nullptr) == size;
}
inline bool WriteManifest(const std::vector<std::wstring>& paths, std::wstring& manifest) {
  std::string encoded;
  if (!EncodePaths(paths, encoded)) return false;
  wchar_t temporary[32768]{};
  const auto length = GetTempPathW(32768, temporary);
  if (!length || length >= 32700) return false;
  auto directory = std::wstring(temporary) + L"VerTree.FileTools.Selections";
  if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return false;
  auto attributes = GetFileAttributesW(directory.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES || !(attributes & FILE_ATTRIBUTE_DIRECTORY) ||
      (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
  // Refuse unbounded handoff accumulation; no arbitrary temp files are deleted.
  WIN32_FIND_DATAW data{};
  HANDLE search = FindFirstFileW((directory + L"\\*.json").c_str(), &data);
  size_t entries = 0;
  if (search != INVALID_HANDLE_VALUE) {
    do { ++entries; } while (entries < 256 && FindNextFileW(search, &data));
    FindClose(search);
  }
  if (entries >= 256) return false;
  GUID guid{}; wchar_t guidText[40]{};
  if (FAILED(CoCreateGuid(&guid)) || !StringFromGUID2(guid, guidText, 40)) return false;
  manifest = directory + L"\\" + std::wstring(guidText + 1, 36) + L".json";
  HANDLE file = CreateFileW(manifest.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
    FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool ok = WriteFile(file, encoded.data(), static_cast<DWORD>(encoded.size()), &written, nullptr) &&
    written == encoded.size();
  CloseHandle(file);
  if (!ok) { DeleteFileW(manifest.c_str()); manifest.clear(); }
  return ok;
}
}
