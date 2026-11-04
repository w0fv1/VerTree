import 'dart:io';

import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

bool isExternalControlPressed() => Platform.isWindows
    ? (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0
    : HardwareKeyboard.instance.isControlPressed;
