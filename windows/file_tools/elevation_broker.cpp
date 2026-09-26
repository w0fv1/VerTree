#include "elevation_broker.h"
#include "file_lock_scanner.h"
#include <shellapi.h>
#include <sddl.h>
#include <bcrypt.h>
#include <array>
#include <iomanip>
#include <sstream>

namespace vt {
namespace {
std::wstring secureNonce() {
  std::array<BYTE, 32> bytes{};
  if (BCryptGenRandom(nullptr, bytes.data(), static_cast<ULONG>(bytes.size()), BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0)
    throw Error("RANDOM_UNAVAILABLE", 0, "A secure IPC nonce could not be generated");
  std::wostringstream result;
  for (auto byte : bytes) result << std::hex << std::setw(2) << std::setfill(L'0') << unsigned(byte);
  return result.str();
}
std::wstring currentSid() {
  HANDLE raw = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw)) failWin32("Open process token");
  Handle token(raw); DWORD size = 0;
  GetTokenInformation(token.get(), TokenUser, nullptr, 0, &size);
  if (size == 0 || size > 65536) throw Error("TOKEN_UNAVAILABLE", 0, "Invalid token size");
  std::vector<BYTE> buffer(size);
  if (!GetTokenInformation(token.get(), TokenUser, buffer.data(), size, &size)) failWin32("Read process token");
  auto user = reinterpret_cast<TOKEN_USER*>(buffer.data());
  LPWSTR text = nullptr;
  if (!ConvertSidToStringSidW(user->User.Sid, &text)) failWin32("Format current SID");
  std::wstring sid(text); LocalFree(text); return sid;
}
class PipeLines {
 public:
  explicit PipeLines(HANDLE pipe) : pipe_(pipe) {}
  bool poll(std::string& line) {
    auto end = buffer_.find('\n');
    if (end != std::string::npos) {
      line = buffer_.substr(0, end); buffer_.erase(0, end + 1); return true;
    }
    DWORD available = 0;
    if (!PeekNamedPipe(pipe_, nullptr, 0, nullptr, &available, nullptr)) failWin32("Read administrator IPC");
    if (!available) return false;
    char bytes[8192]; DWORD received = 0;
    if (!ReadFile(pipe_, bytes, std::min<DWORD>(available, sizeof(bytes)), &received, nullptr) || !received)
      failWin32("Read administrator IPC");
    buffer_.append(bytes, received);
    if (buffer_.size() > kMaxRequestBytes) throw Error("PROTOCOL_LIMIT", 0, "Administrator IPC frame exceeded its bound");
    end = buffer_.find('\n');
    if (end == std::string::npos) return false;
    line = buffer_.substr(0, end); buffer_.erase(0, end + 1); return true;
  }
 private:
  HANDLE pipe_; std::string buffer_;
};
}
Handle connectElevatedPipe(const std::wstring& nonce, DWORD brokerPid, const std::string& birth) {
  if (nonce.size() != 64 || nonce.find_first_not_of(L"0123456789abcdef") != std::wstring::npos)
    throw Error("INVALID_IPC", 0, "Invalid private pipe nonce");
  Handle broker(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, brokerPid));
  if (!broker || processBirth(broker.get()) != birth ||
      !samePath(processImage(broker.get()), executablePath()))
    throw Error("IPC_IDENTITY_MISMATCH", 0, "Administrator broker identity did not match");
  const auto name = L"\\\\.\\pipe\\VerTree.FileTools." + nonce;
  Handle pipe(CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
    SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr));
  if (!pipe) failWin32("Connect private administrator pipe");
  ULONG server = 0;
  if (!GetNamedPipeServerProcessId(pipe.get(), &server) || server != brokerPid)
    throw Error("IPC_IDENTITY_MISMATCH", 0, "Unexpected administrator pipe server");
  Output(pipe.get()).emit({{"type", "hello"}, {"nonce", utf8(nonce)}, {"pid", GetCurrentProcessId()}});
  return pipe;
}
Json runElevated(const Json& request, Control& control, Output& output) {
  const auto op = request.at("op").get<std::string>();
  if (op != "elevatedScan" && op != "elevatedProcess")
    throw Error("ELEVATED_OPERATION_DENIED", 0, "Only usage scans and explicit one-process actions can be elevated");
  const auto nonce = secureNonce();
  const auto pipeName = L"\\\\.\\pipe\\VerTree.FileTools." + nonce;
  const auto sddl = L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;" + currentSid() + L")";
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1, &descriptor, nullptr))
    failWin32("Create private IPC security descriptor");
  SECURITY_ATTRIBUTES security{sizeof(security), descriptor, FALSE};
  Handle pipe(CreateNamedPipeW(pipeName.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
    PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_NOWAIT | PIPE_REJECT_REMOTE_CLIENTS,
    1, 65536, 65536, 0, &security));
  LocalFree(descriptor);
  if (!pipe) failWin32("Create private administrator pipe");
  output.emit({{"type", "scanProgress"}, {"phase", "awaitingAdministrator"}});
  auto args = L"--elevated-pipe " + nonce + L" --broker-pid " + std::to_wstring(GetCurrentProcessId()) +
    L" --broker-birth " + wide(processBirth(GetCurrentProcess()));
  const auto executable = executablePath();
  SHELLEXECUTEINFOW shell{}; shell.cbSize = sizeof(shell);
  shell.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC | SEE_MASK_FLAG_NO_UI;
  shell.lpVerb = L"runas"; shell.lpFile = executable.c_str(); shell.lpParameters = args.c_str(); shell.nShow = SW_HIDE;
  if (!ShellExecuteExW(&shell)) {
    const auto error = GetLastError();
    if (error == ERROR_CANCELLED) throw Error("ELEVATION_CANCELLED", error, "Administrator permission was not granted");
    failWin32("Request administrator permission", error);
  }
  Handle child(shell.hProcess);
  if (!child) throw Error("ELEVATION_FAILED", 0, "The administrator helper did not start");
  const auto deadline = Clock::now() + std::chrono::seconds(100);
  bool connected = false;
  while (Clock::now() < deadline && !control.cancelled) {
    if (ConnectNamedPipe(pipe.get(), nullptr)) { connected = true; break; }
    const auto error = GetLastError();
    if (error == ERROR_PIPE_CONNECTED) { connected = true; break; }
    if (error != ERROR_PIPE_LISTENING && error != ERROR_NO_DATA) failWin32("Connect administrator pipe", error);
    if (WaitForSingleObject(child.get(), 0) == WAIT_OBJECT_0) break;
    Sleep(25);
  }
  if (!connected) throw Error(control.cancelled ? "CANCELLED" : "ELEVATION_FAILED", 0,
    "The administrator helper did not connect; no privileged action was performed");
  ULONG clientPid = 0;
  if (!GetNamedPipeClientProcessId(pipe.get(), &clientPid) || clientPid != GetProcessId(child.get()))
    throw Error("IPC_IDENTITY_MISMATCH", 0, "An unexpected process connected to administrator IPC");
  DWORD mode = PIPE_READMODE_BYTE | PIPE_WAIT;
  if (!SetNamedPipeHandleState(pipe.get(), &mode, nullptr, nullptr)) failWin32("Set administrator pipe mode");
  PipeLines reader(pipe.get()); std::string text;
  while (!reader.poll(text)) {
    if (Clock::now() >= deadline || control.cancelled) throw Error("CANCELLED", 0, "Administrator handshake cancelled");
    Sleep(10);
  }
  auto hello = Json::parse(text);
  if (hello.value("v", 0) != 1 || hello.value("type", "") != "hello" ||
      hello.value("nonce", "") != utf8(nonce) || hello.value("pid", DWORD(0)) != clientPid)
    throw Error("IPC_IDENTITY_MISMATCH", 0, "Invalid administrator handshake");
  Output writer(pipe.get());
  Json privileged = request;
  privileged["op"] = op == "elevatedScan" ? "scan" : "process";
  privileged["brokerPid"] = GetCurrentProcessId();
  writer.emit(privileged);
  bool cancelledSent = false;
  while (Clock::now() < deadline) {
    if (control.cancelled && !cancelledSent) {
      writer.emit({{"control", "cancel"}}); cancelledSent = true;
    }
    if (reader.poll(text)) {
      auto event = Json::parse(text);
      if (event.value("v", 0) != 1) throw Error("PROTOCOL_VERSION", 0, "Unexpected administrator protocol");
      const auto type = event.value("type", "");
      if (type == "result") return event.at("result");
      if (type == "error") throw Error(event.value("code", "ELEVATED_ERROR"), event.value("win32", DWORD(0)), event.value("message", "Administrator operation failed"));
      if (type != "scanProgress" && type != "process" && type != "warning")
        throw Error("PROTOCOL_TYPE", 0, "Unexpected administrator message");
      output.emit(std::move(event));
    } else Sleep(10);
  }
  // Closing the pipe cancels the child's control reader. Its own bounded
  // watchdog handles blocked kernel queries; no foreign process is terminated.
  throw Error("ELEVATED_TIMEOUT", 0, "Administrator operation exceeded its time budget");
}
}
