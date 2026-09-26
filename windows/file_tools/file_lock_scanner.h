#pragma once
#include "common.h"

namespace vt {
// A usage observation is not proof that a handle prevents deletion. Query only;
// never close another process's handle. Results are bounded and best-effort.
Json scanFileUsage(const Json& request, Control& control, Output& output);
Json describeProcess(DWORD pid, DWORD hostPid);
std::wstring processImage(HANDLE process);
std::string processActionRestriction(HANDLE process, DWORD pid, DWORD hostPid);
}
