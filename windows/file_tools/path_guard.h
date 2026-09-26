#pragma once
#include "common.h"

namespace vt {
struct FileMeta {
  std::string identity, volume;
  DWORD attributes = 0, tag = 0;
  uint64_t logicalSize = 0;
  bool directory() const { return (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0; }
  bool reparse() const { return (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0; }
};
FileMeta metadata(HANDLE handle);
std::string identityOf(uint64_t volume, const BYTE* id, uint64_t created);
std::wstring normalizedPath(const std::wstring& input);
std::wstring extendedPath(const std::wstring& input);
std::wstring canonicalHandlePath(HANDLE handle);
void validateDeletePath(const std::wstring& path, const Json& extraProtected = Json::array());
void validateReparse(HANDLE handle, const FileMeta& meta);
struct Binding {
  std::wstring path;
  std::vector<Handle> ancestors;
  std::vector<std::string> ancestorIds;
  Handle target;
  FileMeta meta;
};
Binding bindPath(const std::wstring& path, bool mutate, const Json* expected = nullptr,
  bool removeReadOnly = false);
Json describeTarget(const Binding& binding);
Json prepareTargets(const Json& request);
std::string deviceKey(const std::wstring& path);
int suggestedWorkers(const std::wstring& path);
}
