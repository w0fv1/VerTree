#include "delete_engine.h"
#include <array>
#include <cstring>
#include <deque>
#include <psapi.h>

namespace vt {
namespace {
struct Entry { std::wstring name; FileMeta meta; };
struct Frame {
  Handle handle;
  std::wstring path;
  FileMeta meta;
  std::shared_ptr<Frame> parent;
  std::vector<std::string> rootAncestors;
  std::vector<BYTE> buffer = std::vector<BYTE>(64 * 1024);
  size_t offset = 0, depth = 0;
  bool haveBuffer = false, enumerationDone = false, legacy = false, failureRecorded = false;
  std::atomic<size_t> pending{0};
  std::atomic<bool> unresolved{false};
};
std::vector<std::string> ancestorsOf(const std::shared_ptr<Frame>& frame) {
  std::vector<std::string> nested;
  auto current = frame;
  while (current->parent) { nested.push_back(current->parent->meta.identity); current = current->parent; }
  auto result = current->rootAncestors;
  result.insert(result.end(), nested.rbegin(), nested.rend());
  return result;
}
Json frameTarget(const std::shared_ptr<Frame>& frame) {
  return {{"path", utf8(frame->path)}, {"identity", frame->meta.identity},
    {"ancestors", ancestorsOf(frame)}, {"directory", frame->meta.directory()},
    {"attributes", frame->meta.attributes}, {"tag", frame->meta.tag}};
}
Json entryTarget(const std::shared_ptr<Frame>& parent, const Entry& entry) {
  auto ancestors = ancestorsOf(parent); ancestors.push_back(parent->meta.identity);
  return {{"path", utf8(parent->path + L"\\" + entry.name)}, {"identity", entry.meta.identity},
    {"ancestors", ancestors}, {"directory", entry.meta.directory()},
    {"attributes", entry.meta.attributes}, {"tag", entry.meta.tag}};
}
// One metadata query for NTFS's 64-bit file IDs; the 128-bit fallback preserves
// the same identity checks on filesystems whose IDs do not fit in 64 bits.
FileMeta verifyEntry(HANDLE handle, const FileMeta& expected) {
  BY_HANDLE_FILE_INFORMATION info{};
  if (!GetFileInformationByHandle(handle, &info)) failWin32("GetFileInformationByHandle");
  std::array<BYTE, 16> bytes{};
  uint64_t id = (uint64_t(info.nFileIndexHigh) << 32) | info.nFileIndexLow;
  std::memcpy(bytes.data(), &id, sizeof(id));
  uint64_t volume = std::stoull(expected.volume, nullptr, 16);
  uint64_t created = (uint64_t(info.ftCreationTime.dwHighDateTime) << 32) | info.ftCreationTime.dwLowDateTime;
  auto identity = identityOf(volume, bytes.data(), created);
  if (identity != expected.identity || info.dwVolumeSerialNumber != static_cast<DWORD>(volume)) {
    auto actual = metadata(handle);
    if (actual.identity != expected.identity) throw Error("TARGET_CHANGED", 0, "An enumerated object was replaced");
    return actual;
  }
  DWORD tag = 0;
  if (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
    FILE_ATTRIBUTE_TAG_INFO attribute{};
    if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfo, &attribute, sizeof(attribute))) failWin32("FileAttributeTagInfo");
    tag = attribute.ReparseTag;
  }
  return {identity, expected.volume, info.dwFileAttributes, tag,
    (uint64_t(info.nFileSizeHigh) << 32) | info.nFileSizeLow};
}
bool nextEntry(Frame& frame, Entry& entry) {
  while (!frame.enumerationDone) {
    if (!frame.haveBuffer) {
      auto infoClass = frame.legacy ? FileIdBothDirectoryInfo : FileIdExtdDirectoryInfo;
      if (!GetFileInformationByHandleEx(frame.handle.get(), infoClass, frame.buffer.data(),
          static_cast<DWORD>(frame.buffer.size()))) {
        auto code = GetLastError();
        if (code == ERROR_NO_MORE_FILES) { frame.enumerationDone = true; return false; }
        if (!frame.legacy && (code == ERROR_INVALID_PARAMETER || code == ERROR_NOT_SUPPORTED || code == ERROR_INVALID_FUNCTION)) {
          frame.legacy = true;
          if (!GetFileInformationByHandleEx(frame.handle.get(), FileIdBothDirectoryRestartInfo,
              frame.buffer.data(), static_cast<DWORD>(frame.buffer.size()))) {
            code = GetLastError();
            if (code == ERROR_NO_MORE_FILES) { frame.enumerationDone = true; return false; }
            failWin32("Directory enumeration", code);
          }
        } else failWin32("Directory enumeration", code);
      }
      frame.offset = 0; frame.haveBuffer = true;
    }
    DWORD nameLength = 0, next = 0, attributes = 0, tag = 0;
    uint64_t created = 0, size = 0; std::array<BYTE, 16> id{};
    const wchar_t* name = nullptr;
    if (frame.legacy) {
      if (frame.offset + offsetof(FILE_ID_BOTH_DIR_INFO, FileName) > frame.buffer.size())
        throw Error("ENUMERATION_CORRUPT", 0, "Invalid directory record");
      const auto* record = reinterpret_cast<FILE_ID_BOTH_DIR_INFO*>(frame.buffer.data() + frame.offset);
      nameLength = record->FileNameLength; next = record->NextEntryOffset;
      attributes = record->FileAttributes; created = record->CreationTime.QuadPart;
      size = record->EndOfFile.QuadPart; name = record->FileName;
      std::memcpy(id.data(), &record->FileId.QuadPart, sizeof(uint64_t));
    } else {
      if (frame.offset + offsetof(FILE_ID_EXTD_DIR_INFO, FileName) > frame.buffer.size())
        throw Error("ENUMERATION_CORRUPT", 0, "Invalid directory record");
      const auto* record = reinterpret_cast<FILE_ID_EXTD_DIR_INFO*>(frame.buffer.data() + frame.offset);
      nameLength = record->FileNameLength; next = record->NextEntryOffset;
      attributes = record->FileAttributes; created = record->CreationTime.QuadPart;
      size = record->EndOfFile.QuadPart; name = record->FileName; tag = record->ReparsePointTag;
      std::memcpy(id.data(), record->FileId.Identifier, 16);
    }
    const auto nameOffset = static_cast<size_t>(reinterpret_cast<const BYTE*>(name) - frame.buffer.data());
    if ((nameLength & 1) || nameLength > 65520 || nameOffset + nameLength > frame.buffer.size() ||
        (next && (next < nameOffset + nameLength - frame.offset || frame.offset + next >= frame.buffer.size())))
      throw Error("ENUMERATION_CORRUPT", 0, "Invalid directory record bounds");
    entry.name.assign(name, nameLength / sizeof(wchar_t));
    frame.haveBuffer = next != 0;
    frame.offset += next;
    if (entry.name == L"." || entry.name == L"..") continue;
    auto identity = identityOf(std::stoull(frame.meta.volume, nullptr, 16), id.data(), created);
    entry.meta = {identity, frame.meta.volume, attributes, tag, size};
    return true;
  }
  return false;
}

class Pool {
 public:
  Pool(int count, int initial, Control& control) : desired(initial), control_(control) {
    for (int i = 0; i < count; ++i) threads_.emplace_back([this, i] { loop(i); });
  }
  ~Pool() { finish(); }
  std::atomic<int> desired;
  std::atomic<size_t> peak{0}, queued{0};
  bool submit(size_t cost, std::function<void()> action) {
    std::unique_lock<std::mutex> lock(mutex_);
    while (!control_.cancelled && (queue_.size() >= 4096 || bytes_ + cost > 16 * 1024 * 1024))
      condition_.wait_for(lock, std::chrono::milliseconds(25));
    if (control_.cancelled) return false;
    bytes_ += cost; queue_.push_back({cost, std::move(action)}); queued = queue_.size();
    peak = std::max(peak.load(), queue_.size()); condition_.notify_all(); return true;
  }
  void finish() {
    { std::lock_guard<std::mutex> lock(mutex_); stopping_ = true; }
    condition_.notify_all();
    for (auto& thread : threads_) if (thread.joinable()) thread.join();
    threads_.clear();
  }
 private:
  struct Work { size_t cost; std::function<void()> action; };
  Control& control_;
  std::mutex mutex_; std::condition_variable condition_;
  std::deque<Work> queue_; size_t bytes_ = 0; bool stopping_ = false;
  std::vector<std::thread> threads_;
  void loop(int index) {
    while (true) {
      Work work;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        while (queue_.empty() || (!control_.cancelled &&
            (control_.paused || index >= desired.load()))) {
          if (stopping_ && queue_.empty()) return;
          condition_.wait_for(lock, std::chrono::milliseconds(25));
        }
        work = std::move(queue_.front()); queue_.pop_front(); bytes_ -= work.cost;
        queued = queue_.size(); condition_.notify_all();
      }
      try { work.action(); } catch (...) { control_.cancelled = true; }
    }
  }
};
struct Counters {
  std::atomic<uint64_t> discovered{0}, files{0}, directories{0}, missing{0}, failed{0}, pending{0}, bytes{0};
  std::atomic<uint64_t> operations{0}, micros{0};
  std::atomic<int64_t> firstDeletionMicros{-1};
  std::atomic<DWORD> peakHandleCount{0};
  std::atomic<size_t> peakDepth{0};
  std::atomic<bool> enumerationComplete{false};
};

class Engine {
 public:
  Engine(const Json& request, Control& control, Output& output)
    : request_(request), control_(control), output_(output), started_(Clock::now()) {}
  Json run();
 private:
  const Json& request_; Control& control_; Output& output_; Counters stats_;
  Clock::time_point started_;
  std::mutex failureMutex_; size_t reportBytes_ = 0;
  std::atomic<bool> reportLimit_{false}, enumerationError_{false};
  bool readOnly_ = false;
  void failure(const Json& target, const Error& error);
  bool erase(Handle& handle, HANDLE parent, const std::wstring& name, const FileMeta& meta);
  void processFile(const std::shared_ptr<Frame>& parent, const Entry& entry);
  void processRoot(const Json& target, Pool& pool, bool recursive);
  void retry(Pool& pool);
  Json progress(int workers) const;
};
void Engine::failure(const Json& target, const Error& error) {
  ++stats_.failed;
  std::lock_guard<std::mutex> lock(failureMutex_);
  if (reportLimit_) return;
  auto value = errorJson(error); value["type"] = "failure"; value["target"] = target;
  value["recursive"] = false;
  reportBytes_ += value.dump().size() + 1;
  if (reportBytes_ > kMaxReportBytes) {
    reportLimit_ = true; control_.cancelled = true;
    output_.emit({{"type", "warning"}, {"code", "REPORT_LIMIT"},
      {"message", "Failure report reached its limit; no new deletion work will be scheduled"}});
    return;
  }
  output_.emit(std::move(value));
}
bool Engine::erase(Handle& handle, HANDLE parent, const std::wstring& name, const FileMeta& meta) {
  if (!control_.ready()) return false;
  validateReparse(handle.get(), meta);
  bool changedReadOnly = false;
  if (meta.attributes & FILE_ATTRIBUTE_READONLY) {
    if (!readOnly_) throw Error("READ_ONLY", ERROR_ACCESS_DENIED, "Read-only item preserved; explicit permission is required");
    FILE_BASIC_INFO basic{};
    basic.FileAttributes = meta.attributes & ~FILE_ATTRIBUTE_READONLY;
    if (!basic.FileAttributes) basic.FileAttributes = FILE_ATTRIBUTE_NORMAL;
    if (!SetFileInformationByHandle(handle.get(), FileBasicInfo, &basic, sizeof(basic))) failWin32("Clear read-only attribute");
    changedReadOnly = true;
  }
  FILE_DISPOSITION_INFO disposition{}; disposition.DeleteFile = TRUE;
  if (!SetFileInformationByHandle(handle.get(), FileDispositionInfo, &disposition, sizeof(disposition))) {
    auto code = GetLastError();
    if (changedReadOnly) {
      FILE_BASIC_INFO current{};
      if (GetFileInformationByHandleEx(handle.get(), FileBasicInfo, &current, sizeof(current))) {
        FILE_BASIC_INFO restore{}; restore.FileAttributes = current.FileAttributes | FILE_ATTRIBUTE_READONLY;
        SetFileInformationByHandle(handle.get(), FileBasicInfo, &restore, sizeof(restore));
      }
    }
    failWin32("FileDispositionInfo", code);
  }
  handle.reset();
  // An accepted disposition is not necessarily immediate name removal. Never
  // label logical bytes as reclaimed space, or count pending deletion as done.
  try {
    auto remaining = openRelative(parent, name, FILE_READ_ATTRIBUTES, false);
    const auto actual = metadata(remaining.get());
    if (actual.identity != meta.identity) throw Error("TARGET_CHANGED", 0, "A new object appeared at the deleted name; it was preserved");
    throw Error("DELETE_PENDING", ERROR_DELETE_PENDING, "Deletion accepted; the original object is still awaiting handle closure");
  } catch (const Error& error) {
    if (error.code == "NOT_FOUND") {
      int64_t unset = -1;
      stats_.firstDeletionMicros.compare_exchange_strong(unset,
        std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() - started_).count());
      if (meta.directory()) ++stats_.directories; else ++stats_.files;
      stats_.bytes += meta.directory() ? 0 : meta.logicalSize;
      return true;
    }
    if (error.code == "ACCESS_DENIED" || error.code == "DELETE_PENDING") {
      ++stats_.pending;
      throw Error("DELETE_PENDING", error.native, "Deletion accepted, but name removal is pending or cannot yet be verified");
    }
    throw;
  }
}
void Engine::processFile(const std::shared_ptr<Frame>& parent, const Entry& entry) {
  struct Pending { std::shared_ptr<Frame> frame; ~Pending() { --frame->pending; } } pending{parent};
  if (!control_.ready()) return;
  const auto started = Clock::now();
  try {
    ACCESS_MASK access = DELETE | FILE_READ_ATTRIBUTES;
    if (readOnly_ && (entry.meta.attributes & FILE_ATTRIBUTE_READONLY)) access |= FILE_WRITE_ATTRIBUTES;
    auto handle = openRelative(parent->handle.get(), entry.name, access, true);
    auto actual = verifyEntry(handle.get(), entry.meta);
    if (!erase(handle, parent->handle.get(), entry.name, actual) && control_.cancelled) parent->unresolved = true;
  } catch (const Error& error) {
    if (error.code == "NOT_FOUND") ++stats_.missing;
    else { parent->unresolved = true; failure(entryTarget(parent, entry), error); }
  } catch (const std::exception& error) {
    parent->unresolved = true;
    failure(entryTarget(parent, entry), Error("INTERNAL_ERROR", 0, error.what()));
  }
  ++stats_.operations;
  stats_.micros += static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() - started).count());
}
void Engine::processRoot(const Json& target, Pool& pool, bool recursive) {
  if (!control_.ready()) return;
  ++stats_.discovered;
  try {
    auto path = normalizedPath(wide(target.at("path").get<std::string>()));
    validateDeletePath(path, request_.value("protectedPaths", Json::array()));
    auto binding = bindPath(path, true, &target, readOnly_);
    validateDeletePath(canonicalHandlePath(binding.target.get()), request_.value("protectedPaths", Json::array()));
    validateReparse(binding.target.get(), binding.meta);
    const auto rootName = path.substr(path.find_last_of(L'\\') + 1);
    if (!recursive || !binding.meta.directory() || binding.meta.reparse()) {
      erase(binding.target, binding.ancestors.back().get(), rootName, binding.meta);
      return;
    }
    auto root = std::make_shared<Frame>(); root->handle = std::move(binding.target);
    root->path = path; root->meta = binding.meta; root->rootAncestors = binding.ancestorIds;
    std::vector<std::shared_ptr<Frame>> stack{root};
    while (!stack.empty()) {
      auto frame = stack.back();
      stats_.peakDepth = std::max(stats_.peakDepth.load(), stack.size());
      if (!control_.ready()) {
        while (frame->pending) Sleep(10);
        frame->handle.reset(); stack.pop_back(); continue;
      }
      Entry entry; bool have = false;
      try { have = nextEntry(*frame, entry); }
      catch (const Error& error) {
        frame->unresolved = true; frame->enumerationDone = true; enumerationError_ = true;
        failure(frameTarget(frame), error); frame->failureRecorded = true;
      }
      if (have) {
        ++stats_.discovered;
        if (entry.meta.directory() && !entry.meta.reparse()) {
          if (stack.size() >= kMaxDepth || frame->path.size() + entry.name.size() + 1 > 32750) {
            frame->unresolved = true; enumerationError_ = true;
            failure(entryTarget(frame, entry), Error("DEPTH_LIMIT", 0, "Traversal depth or path budget reached; subtree preserved"));
            continue;
          }
          try {
            ACCESS_MASK access = DELETE | FILE_READ_ATTRIBUTES | FILE_LIST_DIRECTORY;
            if (readOnly_ && (entry.meta.attributes & FILE_ATTRIBUTE_READONLY)) access |= FILE_WRITE_ATTRIBUTES;
            auto handle = openRelative(frame->handle.get(), entry.name, access, true);
            auto actual = verifyEntry(handle.get(), entry.meta);
            // A change to reparse status is not permission to traverse a link.
            if (actual.reparse()) throw Error("TARGET_CHANGED", 0, "Directory became a reparse point");
            auto child = std::make_shared<Frame>(); child->handle = std::move(handle);
            child->path = frame->path + L"\\" + entry.name; child->meta = actual;
            child->parent = frame; stack.push_back(std::move(child));
          } catch (const Error& error) {
            if (error.code == "NOT_FOUND") ++stats_.missing;
            else { frame->unresolved = true; enumerationError_ = true; failure(entryTarget(frame, entry), error); }
          }
        } else {
          ++frame->pending;
          if (!pool.submit(sizeof(Entry) + entry.name.size() * 2 + entry.meta.identity.size(),
              [this, frame, entry] { processFile(frame, entry); })) --frame->pending;
        }
        continue;
      }
      while (frame->pending) Sleep(5);
      if (!control_.cancelled) {
        if (frame->unresolved) {
          if (!frame->failureRecorded) failure(frameTarget(frame), Error("CHILDREN_REMAIN", ERROR_DIR_NOT_EMPTY, "Unresolved children remain; parent was preserved"));
        } else {
          try {
            auto parentHandle = frame->parent ? frame->parent->handle.get() : binding.ancestors.back().get();
            auto name = frame->path.substr(frame->path.find_last_of(L'\\') + 1);
            erase(frame->handle, parentHandle, name, frame->meta);
          } catch (const Error& error) { frame->unresolved = true; failure(frameTarget(frame), error); }
        }
      }
      if (frame->parent && frame->unresolved) frame->parent->unresolved = true;
      frame->handle.reset(); stack.pop_back();
    }
  } catch (const Error& error) {
    if (error.code == "NOT_FOUND") ++stats_.missing;
    else { if (target.value("directory", false)) enumerationError_ = true; failure(target, error); }
  }
}
static bool authorizedRetry(const Json& candidate, const Json& roots) {
  auto path = normalizedPath(wide(candidate.at("path").get<std::string>()));
  const auto ids = candidate.at("ancestors").get<std::vector<std::string>>();
  for (const auto& root : roots) {
    auto rootPath = normalizedPath(wide(root.at("path").get<std::string>()));
    const auto rootIds = root.at("ancestors").get<std::vector<std::string>>();
    if (ids.size() < rootIds.size() || !std::equal(rootIds.begin(), rootIds.end(), ids.begin())) continue;
    if (samePath(rootPath, path)) return candidate.at("identity") == root.at("identity") && ids == rootIds;
    if (root.value("directory", false) && !root.value("tag", 0u) && pathContains(rootPath, path) &&
        ids.size() > rootIds.size() && ids[rootIds.size()] == root.at("identity")) return true;
  }
  return false;
}
void Engine::retry(Pool& pool) {
  auto report = normalizedPath(wide(request_.at("retryReport").get<std::string>()));
  Handle input(CreateFileW(extendedPath(report).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
    OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN, nullptr));
  if (!input) failWin32("Open failure report");
  auto meta = metadata(input.get());
  if (meta.reparse() || meta.directory() || meta.logicalSize > kMaxReportBytes)
    throw Error("INVALID_REPORT", 0, "Failure report is not a bounded ordinary file");
  Lines lines(input.get()); std::string text;
  while (control_.ready() && lines.read(text)) {
    auto event = Json::parse(text);
    if (event.value("type", "") != "failure") continue;
    const auto& target = event.at("target");
    if (!authorizedRetry(target, request_.at("targets")))
      throw Error("INVALID_REPORT", 0, "Failure record falls outside the originally confirmed identities");
    // Never recursively rescan on retry: same-name replacements and newly
    // created children require a new preparation and explicit confirmation.
    processRoot(target, pool, false);
  }
}
Json Engine::progress(int workers) const {
  auto elapsed = std::chrono::duration<double>(Clock::now() - started_).count();
  const auto completed = stats_.files + stats_.directories + stats_.missing + stats_.failed;
  return {{"discovered", stats_.discovered.load()}, {"deletedFiles", stats_.files.load()},
    {"deletedDirectories", stats_.directories.load()}, {"alreadyMissing", stats_.missing.load()},
    {"failedItems", stats_.failed.load()}, {"pendingDelete", stats_.pending.load()},
    {"logicalBytesProcessed", stats_.bytes.load()}, {"enumerationComplete", stats_.enumerationComplete.load()},
    {"percent", nullptr}, {"totalItems", stats_.enumerationComplete ? Json(stats_.discovered.load()) : Json(nullptr)},
    {"itemsPerSecond", elapsed > 0 ? completed / elapsed : 0}, {"elapsedSeconds", elapsed},
    {"activeWorkers", workers}, {"paused", control_.paused.load()}, {"peakDirectoryDepth", stats_.peakDepth.load()}};
}
Json Engine::run() {
  const auto& targets = request_.at("targets");
  if (!targets.is_array() || targets.empty() || targets.size() > kMaxTargets)
    throw Error("SELECTION_LIMIT", 0, "Invalid target count");
  readOnly_ = request_.value("readOnly", false);
  int configured = request_.value("workers", 0);
  if (configured < 0 || configured > 8) throw Error("INVALID_WORKERS", 0, "Worker count must be 0..8");
  int initial = 8;
  for (const auto& target : targets) initial = std::min(initial, suggestedWorkers(wide(target.at("path").get<std::string>())));
  int maximum = initial == 1 ? 2 : 8;
  if (configured) initial = maximum = configured;
  const int allocated = std::clamp(request_.value("maxWorkers", 8), 1, 8);
  maximum = std::min(maximum, allocated); initial = std::min(initial, maximum);
  Pool pool(maximum, initial, control_);
  std::atomic<bool> finished{false};
  std::thread reporter([&] {
    uint64_t previousOperations = 0, previousMicros = 0;
    double previousRate = 0, previousLatency = 0;
    int ticks = 0;
    try {
      while (!finished) {
        DWORD handleCount = 0;
        if (GetProcessHandleCount(GetCurrentProcess(), &handleCount))
          stats_.peakHandleCount = std::max(stats_.peakHandleCount.load(), handleCount);
        output_.emit({{"type", "progress"}, {"progress", progress(pool.desired)}});
        for (int i = 0; i < 10 && !finished; ++i) Sleep(20);
        if (!configured && !control_.paused && ++ticks % 5 == 0) {
          auto operations = stats_.operations.load(), micros = stats_.micros.load();
          auto count = operations - previousOperations;
          double latency = count ? double(micros - previousMicros) / count : 0;
          int current = pool.desired.load();
          if (count > 256 && previousRate > 0 && double(count) < previousRate * 0.8 && latency > previousLatency * 1.5)
            pool.desired = std::max(1, current - 1);
          else if (count > 512 && pool.queued > size_t(current * 8) &&
              (previousRate == 0 || double(count) >= previousRate * 0.95) && current < maximum)
            pool.desired = current + 1;
          previousOperations = operations; previousMicros = micros;
          previousRate = double(count); previousLatency = latency;
        }
      }
    } catch (...) { control_.cancelled = true; }
  });
  std::exception_ptr fatal;
  try {
    if (request_.contains("retryReport")) retry(pool);
    else for (const auto& target : targets) { if (!control_.ready()) break; processRoot(target, pool, true); }
  } catch (...) { fatal = std::current_exception(); control_.cancelled = true; }
  pool.finish();
  stats_.enumerationComplete = !control_.cancelled && !enumerationError_;
  finished = true; if (reporter.joinable()) reporter.join();
  if (fatal) std::rethrow_exception(fatal);
  auto resultProgress = progress(pool.desired); resultProgress["peakQueuedItems"] = pool.peak.load();
  const auto first = stats_.firstDeletionMicros.load();
  resultProgress["firstDeletionSeconds"] = first < 0 ? Json(nullptr) : Json(first / 1000000.0);
  PROCESS_MEMORY_COUNTERS memory{}; memory.cb = sizeof(memory);
  if (GetProcessMemoryInfo(GetCurrentProcess(), &memory, sizeof(memory)))
    resultProgress["peakWorkingSetBytes"] = memory.PeakWorkingSetSize;
  resultProgress["peakSampledHandleCount"] = stats_.peakHandleCount.load();
  std::string outcome = reportLimit_ ? "partial" : control_.cancelled ? "cancelled" : stats_.failed ? "partial" : "succeeded";
  if (outcome == "succeeded") resultProgress["percent"] = 1.0;
  return {{"outcome", outcome}, {"progress", resultProgress}, {"reportComplete", !reportLimit_},
    {"message", reportLimit_ ? "Failure-report budget exhausted; remaining items preserved" : ""}};
}
}
Json executeDeletion(const Json& request, Control& control, Output& output) { return Engine(request, control, output).run(); }
}
