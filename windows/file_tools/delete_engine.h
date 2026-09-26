#pragma once
#include "path_guard.h"

namespace vt {
// The caller must supply targets returned by prepareTargets and obtain explicit
// user confirmation. Retries are non-recursive and identity-bound.
Json executeDeletion(const Json& request, Control& control, Output& output);
}
