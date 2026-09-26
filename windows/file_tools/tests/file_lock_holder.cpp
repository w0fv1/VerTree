#include "common.h"
#include <iostream>

// Test fixture only: never packaged. It keeps a read handle without sharing
// delete until stdin receives a line. Integration tests may end only this child.
int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  vt::Handle handle(CreateFileW(argv[1], GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
    nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
  if (!handle) return 3;
  std::cout << vt::Json({{"pid", GetCurrentProcessId()},
    {"creationTime", vt::processBirth(GetCurrentProcess())}}).dump() << std::endl;
  std::string command;
  std::getline(std::cin, command);
  return 0;
}
