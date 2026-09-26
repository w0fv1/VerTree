#pragma once
#include <windows.h>
#include <winternl.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include "third_party/nlohmann/json.hpp"

namespace vt {
using Json = nlohmann::json;
using Clock = std::chrono::steady_clock;
constexpr size_t kMaxRequestBytes = 4 * 1024 * 1024;
constexpr size_t kMaxReportBytes = 32 * 1024 * 1024;
constexpr size_t kMaxTargets = 1024;
constexpr size_t kMaxDepth = 256;

class Handle {
 public:
  Handle() = default;
  explicit Handle(HANDLE value) : value_(value) {}
  ~Handle() { reset(); }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  Handle(Handle&& other) noexcept : value_(other.release()) {}
  Handle& operator=(Handle&& other) noexcept {
    if (this != &other) reset(other.release());
    return *this;
  }
  explicit operator bool() const { return value_ && value_ != INVALID_HANDLE_VALUE; }
  HANDLE get() const { return value_; }
  HANDLE release() { auto value = value_; value_ = nullptr; return value; }
  void reset(HANDLE value = nullptr) {
    if (*this) CloseHandle(value_);
    value_ = value;
  }
 private:
  HANDLE value_ = nullptr;
};

struct Error : std::runtime_error {
  Error(std::string code, DWORD native, const std::string& message)
    : std::runtime_error(message), code(std::move(code)), native(native) {}
  std::string code;
  DWORD native;
};
std::string utf8(const std::wstring& value);
std::wstring wide(const std::string& value);
std::string hex64(uint64_t value);
std::string errorCode(DWORD value);
std::string errorMessage(DWORD value);
[[noreturn]] void failWin32(const char* operation, DWORD error = GetLastError());
std::wstring executablePath();
std::wstring environment(const wchar_t* name);
bool samePath(const std::wstring& a, const std::wstring& b);
bool pathContains(const std::wstring& parent, const std::wstring& child);
std::string processBirth(HANDLE process);
Json errorJson(const Error& error);

class Output {
 public:
  explicit Output(HANDLE handle = GetStdHandle(STD_OUTPUT_HANDLE)) : handle_(handle) {}
  void emit(Json value);
 private:
  HANDLE handle_;
  std::mutex mutex_;
  uint64_t sequence_ = 0;
};

// Bounded, cancellable synchronous reader. No detached iostream thread.
class Lines {
 public:
  explicit Lines(HANDLE handle) : handle_(handle) {}
  bool read(std::string& line, size_t limit = kMaxRequestBytes);
  std::string releaseBuffered() { auto value = std::move(buffered_); buffered_.clear(); return value; }
 private:
  HANDLE handle_;
  std::string buffered_;
};

class Control {
 public:
  std::atomic<bool> cancelled{false}, paused{false};
  bool ready() const;
  void command(const Json& value);
};

using NtCreateFileFn = NTSTATUS (NTAPI*)(PHANDLE, ACCESS_MASK, POBJECT_ATTRIBUTES,
  PIO_STATUS_BLOCK, PLARGE_INTEGER, ULONG, ULONG, ULONG, ULONG, PVOID, ULONG);
using NtQuerySystemInformationFn = NTSTATUS (NTAPI*)(ULONG, PVOID, ULONG, PULONG);
using NtQueryObjectFn = NTSTATUS (NTAPI*)(HANDLE, ULONG, PVOID, ULONG, PULONG);
using RtlNtStatusToDosErrorFn = ULONG (WINAPI*)(NTSTATUS);
struct NtApi {
  NtApi();
  NtCreateFileFn create;
  NtQuerySystemInformationFn system;
  NtQueryObjectFn object;
  RtlNtStatusToDosErrorFn toDos;
};
NtApi& nt();
Handle openRelative(HANDLE parent, const std::wstring& name, ACCESS_MASK access,
  bool pin, bool exactCase = true);
}
