#pragma once
#ifndef JSON_NOEXCEPTION
#define JSON_NOEXCEPTION
#endif
#include "../file_tools/third_party/nlohmann/json.hpp"
#include <string>

namespace vertree_menu {
using Json = nlohmann::json;
inline Json ParsePreferences(const std::string& content) {
  auto config = Json::parse(content, nullptr, false);
  if (!config.is_object()) return Json{{"win11MenuEnabled", false}};
  return config;
}
inline bool Enabled(const Json& config) {
  const auto it = config.find("win11MenuEnabled");
  return it == config.end() || (it->is_boolean() && it->get<bool>());
}
inline bool Selected(const Json& config, const char* action) {
  const auto it = config.find("windows11MenuActions");
  if (it == config.end()) return true;
  if (!it->is_array()) return false;
  for (const auto& value : *it) {
    if (value.is_string() && value.get_ref<const std::string&>() == action) return true;
  }
  return false;
}
}  // namespace vertree_menu
