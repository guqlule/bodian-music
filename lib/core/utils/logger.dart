import 'package:flutter/foundation.dart';

/// 统一日志出口：release 包自动静默，debug 输出到控制台
void logDebug(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
