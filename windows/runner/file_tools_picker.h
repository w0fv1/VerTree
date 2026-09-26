#pragma once
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterFileToolsPicker(flutter::BinaryMessenger* messenger, HWND owner);
