#include "common.h"
#include "path_guard.h"
#include "delete_engine.h"
#include "file_lock_scanner.h"
#include "process_actions.h"
#include "elevation_broker.h"
#include <iostream>

namespace vt {
namespace {
class SessionGuard {
 public:
  SessionGuard(HANDLE input, Control& control, DWORD parentPid, int deadlineSeconds, std::string initial)
    : control_(control), deadline_(deadlineSeconds > 0 ? Clock::now() + std::chrono::seconds(deadlineSeconds) : Clock::time_point::max()) {
    if (parentPid && parentPid != GetCurrentProcessId()) {
      parent_.reset(OpenProcess(SYNCHRONIZE, FALSE, parentPid));
      if (!parent_) throw Error("HOST_UNAVAILABLE", 0, "The controlling process is unavailable");
    }
    reader_ = std::thread([this, input, initial = std::move(initial)] {
      std::string buffered = initial;
      try {
        while (!done_) {
          size_t bufferedEnd;
          while ((bufferedEnd = buffered.find('\n')) != std::string::npos) {
            auto line = buffered.substr(0, bufferedEnd); buffered.erase(0, bufferedEnd + 1);
            control_.command(Json::parse(line));
          }
          DWORD available = 0;
          if (!PeekNamedPipe(input, nullptr, 0, nullptr, &available, nullptr)) {
            control_.cancelled = true; return;
          }
          if (!available) { Sleep(20); continue; }
          char data[4096]; DWORD size = 0;
          if (!ReadFile(input, data, std::min<DWORD>(available, sizeof(data)), &size, nullptr) || !size) {
            control_.cancelled = true; return;
          }
          buffered.append(data, size);
          if (buffered.size() > 16384) { control_.cancelled = true; return; }
          size_t end;
          while ((end = buffered.find('\n')) != std::string::npos) {
            auto line = buffered.substr(0, end); buffered.erase(0, end + 1);
            auto value = Json::parse(line); control_.command(value);
          }
        }
      } catch (...) { control_.cancelled = true; }
    });
    watchdog_ = std::thread([this] {
      auto cancellationAt = Clock::time_point::max();
      while (!done_) {
        if (parent_ && WaitForSingleObject(parent_.get(), 0) == WAIT_OBJECT_0) control_.cancelled = true;
        if (Clock::now() >= deadline_) control_.cancelled = true;
        if (control_.cancelled) {
          if (cancellationAt == Clock::time_point::max()) cancellationAt = Clock::now();
          if (Clock::now() - cancellationAt >= std::chrono::seconds(8)) {
            // Only terminate this isolated helper, never a user process. This
            // also bounds a stuck kernel query after parent death/cancellation.
            TerminateProcess(GetCurrentProcess(), ERROR_OPERATION_ABORTED);
            return;
          }
        }
        Sleep(50);
      }
    });
  }
  ~SessionGuard() {
    done_ = true;
    if (reader_.joinable()) reader_.join();
    if (watchdog_.joinable()) watchdog_.join();
  }
 private:
  Control& control_; Handle parent_; Clock::time_point deadline_;
  std::atomic<bool> done_{false}; std::thread reader_, watchdog_;
};
int serve(HANDLE input, HANDLE destination, bool elevated, DWORD brokerPid) {
  Output output(destination);
  try {
    Lines reader(input); std::string text;
    if (!reader.read(text)) throw Error("MISSING_REQUEST", 0, "A versioned JSON request on stdin is required");
    auto request = Json::parse(text);
    if (request.value("v", 0) != 1) throw Error("PROTOCOL_VERSION", 0, "Unsupported file-tools protocol");
    const auto operation = request.at("op").get<std::string>();
    if (elevated && operation != "scan" && operation != "process")
      throw Error("ELEVATED_OPERATION_DENIED", 0, "Administrator helpers cannot delete files or execute arbitrary commands");
    Control control; control.paused = request.value("initialPaused", false);
    int deadline = operation == "scan" ? 65 : operation == "process" ? 100 :
      operation == "elevatedScan" || operation == "elevatedProcess" ? 180 : operation == "prepare" ? 30 : 0;
    SessionGuard guard(input, control, elevated ? brokerPid : request.value("hostPid", DWORD(0)), deadline, reader.releaseBuffered());
    Json result;
    if (operation == "prepare") result = prepareTargets(request);
    else if (operation == "delete") {
      if (!request.value("confirmed", false)) throw Error("CONFIRMATION_REQUIRED", 0, "Permanent deletion was not confirmed");
      result = executeDeletion(request, control, output);
    } else if (operation == "scan") result = scanFileUsage(request, control, output);
    else if (operation == "process") result = actOnProcess(request, control, output, elevated);
    else if (operation == "elevatedScan" || operation == "elevatedProcess") result = runElevated(request, control, output);
    else throw Error("UNKNOWN_OPERATION", 0, "Unknown file-tools operation");
    output.emit({{"type", "result"}, {"result", result}});
    return 0;
  } catch (const Error& error) {
    try { auto value = errorJson(error); value["type"] = "error"; output.emit(value); } catch (...) {}
    return 2;
  } catch (const std::exception& error) {
    try { output.emit({{"type", "error"}, {"code", "INVALID_REQUEST_OR_INTERNAL_ERROR"}, {"message", error.what()}}); } catch (...) {}
    return 3;
  }
}
}
}
int wmain(int argc, wchar_t** argv) {
  // A console endpoint intended for framed stdin/stdout, not shell path parsing.
  // No command-line switch can delete a path or terminate another process.
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
  try {
    if (argc == 7 && std::wstring(argv[1]) == L"--elevated-pipe" &&
        std::wstring(argv[3]) == L"--broker-pid" && std::wstring(argv[5]) == L"--broker-birth") {
      const auto broker = static_cast<DWORD>(std::stoul(argv[4]));
      auto pipe = vt::connectElevatedPipe(argv[2], broker, vt::utf8(argv[6]));
      return vt::serve(pipe.get(), pipe.get(), true, broker);
    }
    if (argc == 2 && std::wstring(argv[1]) == L"--version") {
      std::cout << "VerTree file worker protocol 1\n"; return 0;
    }
    if (argc != 2 || std::wstring(argv[1]) != L"--stdio") {
      std::cerr << "Usage: vertree_file_worker --stdio (versioned JSON protocol; no direct destructive CLI)\n";
      return 2;
    }
    return vt::serve(GetStdHandle(STD_INPUT_HANDLE), GetStdHandle(STD_OUTPUT_HANDLE), false, 0);
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n'; return 2;
  }
}
