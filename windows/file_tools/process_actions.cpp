#include "process_actions.h"
#include "file_lock_scanner.h"
#include "identity_bound_scan.h"

namespace vt {
namespace {
struct CloseWindows { DWORD pid; unsigned requested = 0; };
BOOL CALLBACK requestClose(HWND window, LPARAM parameter) {
  auto& context = *reinterpret_cast<CloseWindows*>(parameter);
  DWORD owner = 0; GetWindowThreadProcessId(window, &owner);
  if (owner == context.pid && IsWindowVisible(window) &&
      PostMessageW(window, WM_CLOSE, 0, 0)) ++context.requested;
  return TRUE;
}
}
Json actOnProcess(const Json& request, Control& control, Output& output, bool elevated) {
  const DWORD pid = request.at("pid").get<DWORD>();
  const auto creation = request.at("creationTime").get<std::string>();
  const auto action = request.at("action").get<std::string>();
  if ((action != "close" && action != "terminate") || !request.value("confirmed", false))
    throw Error("CONFIRMATION_REQUIRED", 0, "A specific, explicitly confirmed process action is required");
  if (request.value("automaticDelete", false) &&
      (!request.contains("expectedTargets") || !request.value("exactPaths", false)))
    throw Error("OBJECT_IDENTITY_REQUIRED", 0, "Automatic obstacle handling requires original failed object identities");
  if (creation.size() != 16) throw Error("PROCESS_IDENTITY_REQUIRED", 0, "PID and creation time are required");
  Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE |
    (action == "terminate" ? PROCESS_TERMINATE : 0), FALSE, pid));
  if (!process) failWin32("Open selected process");
  if (WaitForSingleObject(process.get(), 0) == WAIT_OBJECT_0)
    return {{"status", "alreadyExited"}, {"pid", pid}};
  if (processBirth(process.get()) != creation)
    throw Error("PROCESS_CHANGED", 0, "PID was reused; refresh the usage list");
  const auto restriction = processActionRestriction(process.get(), pid, request.value("hostPid", DWORD(0)));
  if (!restriction.empty()) throw Error(restriction, ERROR_ACCESS_DENIED,
    "System, service, protected, unverified, and VerTree host processes are not actionable");

  // Pin original objects/ancestors until the action ends. Do not validate paths
  // only once and then terminate a process that is using a replacement object.
  std::vector<Binding> identityPins;
  if (request.contains("expectedTargets")) {
    const auto& expected = request.at("expectedTargets");
    const auto& paths = request.at("paths");
    if (!request.value("exactPaths", false) || !expected.is_array() || expected.empty() ||
        expected.size() != paths.size() || expected.size() > kMaxTargets)
      throw Error("INVALID_EXPECTED_TARGETS", 0, "Exact file identities are required");
    for (size_t index = 0; index < expected.size(); ++index) {
      if (!samePath(normalizedPath(wide(paths.at(index).get<std::string>())),
          normalizedPath(wide(expected.at(index).at("path").get<std::string>()))))
        throw Error("INVALID_EXPECTED_TARGETS", 0, "The target does not match the requested identity");
      identityPins.push_back(bindExpectedUsage(expected.at(index), request.value("protectedPaths", Json::array())));
    }
  }

  auto scanRequest = request;
  scanRequest["onlyPid"] = pid; scanRequest["budgetSeconds"] = 15;
  auto scan = scanFileUsage(scanRequest, control, output);
  bool stillUsesSelection = false;
  for (const auto& match : scan.at("processes")) {
    if (match.at("pid") == pid && match.at("creationTime") == creation && !match.at("files").empty())
      stillUsesSelection = true;
  }
  if (!stillUsesSelection) throw Error("USAGE_CHANGED", 0,
    "The selected process no longer has a verified relationship to these paths; it was left running");
  if (!control.ready()) throw Error("CANCELLED", ERROR_OPERATION_ABORTED, "Process action cancelled");
  if (processBirth(process.get()) != creation)
    throw Error("PROCESS_CHANGED", 0, "Process identity changed");
  if (WaitForSingleObject(process.get(), 0) == WAIT_OBJECT_0)
    return {{"status", "alreadyExited"}, {"pid", pid}};
  if (elevated) {
    const auto image = processImage(process.get());
    const std::wstring message = L"VerTree: " + std::wstring(action == "terminate" ?
      L"End this process? Unsaved work in this application may be lost.\n\n" :
      L"Request this application to close?\n\n") + image + L"\nPID: " + std::to_wstring(pid) +
      L"\n\nOnly this process will be affected. No process tree or individual file handle will be forcibly closed.";
    if (MessageBoxW(nullptr, message.c_str(), L"VerTree - Confirm administrator action",
        MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2 | MB_SETFOREGROUND) != IDYES)
      throw Error("CANCELLED", ERROR_CANCELLED, "Administrator action was not confirmed");
  }
  if (!control.ready()) throw Error("CANCELLED", ERROR_OPERATION_ABORTED, "Process action cancelled");
  if (action == "close") {
    CloseWindows context{pid};
    EnumWindows(requestClose, reinterpret_cast<LPARAM>(&context));
    const auto wait = WaitForSingleObject(process.get(), 2000);
    return {{"status", wait == WAIT_OBJECT_0 ? "exited" : context.requested ? "closeRequested" : "noClosableWindow"},
      {"pid", pid}, {"windowsNotified", context.requested}};
  }
  // Wait with the same identity-bound process handle; API success is not exit.
  if (!TerminateProcess(process.get(), ERROR_PROCESS_ABORTED)) failWin32("Terminate selected process");
  auto wait = WaitForSingleObject(process.get(), 5000);
  if (wait == WAIT_FAILED) failWin32("Wait for selected process");
  return {{"status", wait == WAIT_OBJECT_0 ? "exited" : "terminationPending"}, {"pid", pid}};
}
}
