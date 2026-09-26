#include "delete_engine.h"
#include "file_lock_scanner.h"
#include <winioctl.h>
#include <filesystem>
#include <future>
#include <iostream>
#include <cstring>

using namespace vt;
namespace fs = std::filesystem;
namespace {
void require(bool condition, const char* message) { if (!condition) throw std::runtime_error(message); }
struct Fixture {
  std::wstring root;
  Fixture() {
    wchar_t temp[32768]{}, file[32768]{};
    require(GetTempPathW(32768, temp) != 0, "GetTempPath failed");
    require(GetTempFileNameW(temp, L"vtf", 0, file) != 0, "GetTempFileName failed");
    root = file; require(DeleteFileW(file), "Remove own placeholder failed");
    require(CreateDirectoryW(file, nullptr), "Create own fixture failed");
  }
  ~Fixture() {
    // Every fixture is a new exclusive OS-generated temporary directory. No
    // user-supplied path enters this cleanup routine.
    std::error_code error; fs::remove_all(root, error);
  }
  std::wstring path(const wchar_t* leaf) const { return root + L"\\" + leaf; }
};
void directory(const std::wstring& path) { require(CreateDirectoryW(extendedPath(path).c_str(), nullptr), "mkdir failed"); }
void file(const std::wstring& path, const char* text = "fixture") {
  Handle output(CreateFileW(extendedPath(path).c_str(), GENERIC_WRITE, FILE_SHARE_READ,
    nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
  require(bool(output), "create fixture file failed");
  DWORD written = 0;
  require(WriteFile(output.get(), text, static_cast<DWORD>(std::strlen(text)), &written, nullptr), "write fixture failed");
}
bool exists(const std::wstring& path) { return GetFileAttributesW(extendedPath(path).c_str()) != INVALID_FILE_ATTRIBUTES; }
Json plan(const std::wstring& path) {
  auto result = prepareTargets({{"paths", Json::array({utf8(path)})}});
  result["confirmed"] = true; return result;
}
Json remove(const Json& request, Control* supplied = nullptr, HANDLE outputHandle = nullptr) {
  Handle sink;
  if (!outputHandle) {
    sink.reset(CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr));
    outputHandle = sink.get();
  }
  Output output(outputHandle); Control control;
  return executeDeletion(request, supplied ? *supplied : control, output);
}
void junction(const std::wstring& link, const std::wstring& target) {
  directory(link);
  const auto substitute = L"\\??\\" + target;
  const size_t strings = (substitute.size() + 1 + target.size() + 1) * sizeof(wchar_t);
  std::vector<BYTE> data(16 + strings);
  const DWORD tag = IO_REPARSE_TAG_MOUNT_POINT;
  const WORD dataLength = static_cast<WORD>(8 + strings);
  const WORD zero = 0, subLength = static_cast<WORD>(substitute.size() * 2);
  const WORD printOffset = static_cast<WORD>(subLength + 2), printLength = static_cast<WORD>(target.size() * 2);
  std::memcpy(data.data(), &tag, 4); std::memcpy(data.data() + 4, &dataLength, 2);
  std::memcpy(data.data() + 8, &zero, 2); std::memcpy(data.data() + 10, &subLength, 2);
  std::memcpy(data.data() + 12, &printOffset, 2); std::memcpy(data.data() + 14, &printLength, 2);
  std::memcpy(data.data() + 16, substitute.c_str(), subLength + 2);
  std::memcpy(data.data() + 16 + printOffset, target.c_str(), printLength + 2);
  Handle handle(CreateFileW(extendedPath(link).c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  require(bool(handle), "open fixture junction failed");
  DWORD returned = 0;
  require(DeviceIoControl(handle.get(), FSCTL_SET_REPARSE_POINT, data.data(), static_cast<DWORD>(data.size()),
    nullptr, 0, &returned, nullptr), "create fixture junction failed");
}
void ordinaryTree() {
  Fixture f; directory(f.path(L"tree"));
  for (int d = 0; d < 20; ++d) {
    auto parent = f.path(L"tree") + L"\\d" + std::to_wstring(d); directory(parent);
    for (int n = 0; n < 50; ++n) file(parent + L"\\f" + std::to_wstring(n));
  }
  auto request = plan(f.path(L"tree")); request["workers"] = 4;
  auto result = remove(request);
  require(result.at("outcome") == "succeeded", result.dump().c_str());
  require(result.at("progress").at("deletedFiles") == 1000, "incorrect file count");
  require(result.at("progress").at("deletedDirectories") == 21, "incorrect directory count");
  require(!exists(f.path(L"tree")), "tree remained");
}
void rootReplacement() {
  Fixture f; file(f.path(L"file")); auto request = plan(f.path(L"file"));
  require(MoveFileW(f.path(L"file").c_str(), f.path(L"original").c_str()), "rename fixture failed");
  file(f.path(L"file"), "new identity"); auto result = remove(request);
  require(result.at("outcome") == "partial", "replacement was not rejected");
  require(exists(f.path(L"file")) && exists(f.path(L"original")), "replacement/original was removed");
}
void parentReplacement() {
  Fixture f; directory(f.path(L"parent")); file(f.path(L"parent\\file"));
  auto request = plan(f.path(L"parent\\file"));
  require(MoveFileW(f.path(L"parent").c_str(), f.path(L"old").c_str()), "rename parent failed");
  directory(f.path(L"parent")); file(f.path(L"parent\\file"));
  auto result = remove(request); require(result.at("outcome") == "partial", "ancestor replacement accepted");
  require(exists(f.path(L"parent\\file")) && exists(f.path(L"old\\file")), "ancestor replacement deleted data");
}
void linkBoundary() {
  Fixture f; directory(f.path(L"outside")); file(f.path(L"outside\\sentinel"));
  directory(f.path(L"tree")); junction(f.path(L"tree\\link"), f.path(L"outside"));
  auto result = remove(plan(f.path(L"tree")));
  require(result.at("outcome") == "succeeded", result.dump().c_str());
  require(exists(f.path(L"outside\\sentinel")), "junction target was traversed");
  junction(f.path(L"link"), f.path(L"outside"));
  bool rejected = false;
  try { plan(f.path(L"link\\sentinel")); } catch (const Error& e) { rejected = e.code == "REPARSE_ANCESTOR"; }
  require(rejected, "reparse ancestor was not rejected");
  require(remove(plan(f.path(L"link"))).at("outcome") == "succeeded", "direct junction unlink failed");
}
void partialAndRetry() {
  Fixture f; directory(f.path(L"tree")); file(f.path(L"tree\\locked")); file(f.path(L"tree\\free"));
  auto request = plan(f.path(L"tree"));
  Handle held(CreateFileW(f.path(L"tree\\locked").c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
    nullptr, OPEN_EXISTING, 0, nullptr)); require(bool(held), "fixture lock failed");
  Handle report(CreateFileW(f.path(L"report.jsonl").c_str(), GENERIC_WRITE, FILE_SHARE_READ,
    nullptr, CREATE_NEW, 0, nullptr));
  auto result = remove(request, nullptr, report.get());
  require(result.at("outcome") == "partial", "locked tree should be partial");
  require(!exists(f.path(L"tree\\free")) && exists(f.path(L"tree\\locked")), "failure blocked independent work");
  held.reset(); report.reset();
  request["retryReport"] = utf8(f.path(L"report.jsonl"));
  result = remove(request);
  require(result.at("outcome") == "succeeded", result.dump().c_str());
  require(!exists(f.path(L"tree")), "retry failed to clean original remaining items");
}
void readOnly() {
  Fixture f; file(f.path(L"file"));
  require(SetFileAttributesW(f.path(L"file").c_str(), FILE_ATTRIBUTE_READONLY), "set read-only failed");
  auto request = plan(f.path(L"file"));
  require(remove(request).at("outcome") == "partial" && exists(f.path(L"file")), "read-only was removed without consent");
  request["readOnly"] = true;
  require(remove(request).at("outcome") == "succeeded", "explicit read-only deletion failed");
}
void sparseLargeFile() {
  Fixture f; auto path = f.path(L"large.bin");
  Handle handle(CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_NEW, 0, nullptr));
  require(bool(handle), "create sparse fixture failed"); DWORD bytes = 0;
  require(DeviceIoControl(handle.get(), FSCTL_SET_SPARSE, nullptr, 0, nullptr, 0, &bytes, nullptr), "set sparse failed");
  LARGE_INTEGER length{}; length.QuadPart = 50LL * 1024 * 1024 * 1024;
  require(SetFilePointerEx(handle.get(), length, nullptr, FILE_BEGIN) && SetEndOfFile(handle.get()), "size sparse failed");
  handle.reset(); auto result = remove(plan(path));
  require(result.at("outcome") == "succeeded", "large-file deletion failed");
  require(result.at("progress").at("logicalBytesProcessed") == length.QuadPart, "logical byte count truncated");
}
void cancelledPause() {
  Fixture f; directory(f.path(L"tree")); file(f.path(L"tree\\keep"));
  auto request = plan(f.path(L"tree")); Control control; control.paused = true;
  auto future = std::async(std::launch::async, [&] { return remove(request, &control); });
  Sleep(100); require(exists(f.path(L"tree\\keep")), "paused task deleted a file");
  control.cancelled = true; control.paused = false;
  auto result = future.get(); require(result.at("outcome") == "cancelled", "cancelled result was not preserved");
  require(exists(f.path(L"tree\\keep")), "cancel deleted queued data");
}
void guards() {
  bool root = false, windows = false, relative = false;
  try { validateDeletePath(L"C:\\"); } catch (const Error&) { root = true; }
  wchar_t path[32768]{}; GetWindowsDirectoryW(path, 32768);
  try { validateDeletePath(path); } catch (const Error&) { windows = true; }
  try { normalizedPath(L"..\\file"); } catch (const Error&) { relative = true; }
  require(root && windows && relative, "protected path validation failed");
  require(!pathContains(L"C:\\work\\a", L"C:\\work\\abc"), "path boundary matched sibling");
  require(processActionRestriction(GetCurrentProcess(), GetCurrentProcessId(), 0) == "SYSTEM_OR_SELF", "self action was not blocked");
}
}
int main() {
  const std::pair<const char*, void(*)()> tests[] = {
    {"ordinary bounded parallel tree", ordinaryTree}, {"root identity replacement", rootReplacement},
    {"ancestor identity replacement", parentReplacement}, {"junction no-follow boundary", linkBoundary},
    {"partial result and identity-bound retry", partialAndRetry}, {"explicit read-only consent", readOnly},
    {"50 GiB sparse logical file", sparseLargeFile}, {"paused cancellation", cancelledPause}, {"path/process guards", guards},
  };
  int failed = 0;
  for (const auto& test : tests) {
    try { test.second(); std::cout << "PASS " << test.first << '\n'; }
    catch (const std::exception& error) { ++failed; std::cerr << "FAIL " << test.first << ": " << error.what() << '\n'; }
  }
  std::cout << (std::size(tests) - failed) << "/" << std::size(tests) << " passed\n";
  return failed ? 1 : 0;
}
