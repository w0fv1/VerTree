#pragma once
#include "path_guard.h"

namespace vt {
// Used only for automatic deletion recovery. Keep the object and every ancestor
// pinned while checking process usage; a reused name must never authorize a kill.
inline Binding bindExpectedUsage(const Json& expected, const Json& protectedPaths) {
  const auto path = normalizedPath(wide(expected.at("path").get<std::string>()));
  validateDeletePath(path, protectedPaths);
  auto binding = bindPath(path, false, &expected);
  if (binding.meta.reparse())
    throw Error("REPARSE_TARGET", 0, "Automatic obstacle handling does not follow links");
  return binding;
}

inline Handle openUsageTarget(const Json& request, const std::wstring& path,
    size_t index, std::vector<Binding>& pinned) {
  if (!request.contains("expectedTargets")) {
    return Handle(CreateFileW(extendedPath(path).c_str(), 0,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS, nullptr));
  }
  const auto& expected = request.at("expectedTargets");
  if (!request.value("exactPaths", false) || !expected.is_array() ||
      expected.size() != request.at("paths").size())
    throw Error("INVALID_EXPECTED_TARGETS", 0, "One exact object identity is required for every path");
  const auto& target = expected.at(index);
  if (!samePath(path, normalizedPath(wide(target.at("path").get<std::string>()))))
    throw Error("INVALID_EXPECTED_TARGETS", 0, "The requested path differs from its original identity");
  auto binding = bindExpectedUsage(target, request.value("protectedPaths", Json::array()));
  auto handle = std::move(binding.target);
  pinned.push_back(std::move(binding));
  return handle;
}
}
