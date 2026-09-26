#pragma once
#include "common.h"
namespace vt {
// Explicit one-process action; no process-tree termination and no foreign-handle closure.
Json actOnProcess(const Json& request, Control& control, Output& output, bool elevated = false);
}
