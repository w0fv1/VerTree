#ifdef _WIN32
#include <windows.h>
#define EXPORT __declspec(dllexport)
#else
#include <errno.h>
#include <unistd.h>
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

/* Capture thread-local errors before returning through the Dart FFI runtime.
 * There must be no intervening FFI call between publication and error capture.
 * Return zero on success; otherwise return the native error code. */
EXPORT int vertree_publish_file(const void *source, const void *destination) {
#ifdef _WIN32
  if (MoveFileExW((const wchar_t *)source, (const wchar_t *)destination,
                  MOVEFILE_WRITE_THROUGH)) return 0;
  return (int)GetLastError();
#else
  if (link((const char *)source, (const char *)destination) == 0) return 0;
  return errno;
#endif
}
