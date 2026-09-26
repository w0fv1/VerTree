#pragma once
#include "common.h"
namespace vt {
// Launch this same executable through UAC for exactly one scan or process action.
// Privileged deletion and arbitrary commands are deliberately not exposed.
Json runElevated(const Json& request, Control& control, Output& output);
Handle connectElevatedPipe(const std::wstring& nonce, DWORD brokerPid, const std::string& birth);
}
