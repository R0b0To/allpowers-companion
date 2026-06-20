import 'package:flutter/foundation.dart';

/// Lightweight structured logger.
///
/// In debug mode writes to the debug console with level prefixes.
/// In release mode all output is suppressed (debugPrint is a no-op in
/// release builds, and we add an explicit kReleaseMode guard for safety).
abstract final class Log {
  static void d(String tag, String message) {
    if (kDebugMode) debugPrint('[ DEBUG ] $tag: $message');
  }

  static void i(String tag, String message) {
    if (kDebugMode) debugPrint('[  INFO ] $tag: $message');
  }

  static void w(String tag, String message) {
    if (kDebugMode) debugPrint('[  WARN ] $tag: $message');
  }

  static void e(String tag, String message, [Object? error, StackTrace? stack]) {
    if (kDebugMode) {
      debugPrint('[ ERROR ] $tag: $message${error != null ? ' — $error' : ''}');
      if (stack != null) debugPrint(stack.toString());
    }
    // In a real production app, forward to a crash-reporting service here
    // (e.g. FirebaseCrashlytics.instance.recordError(error, stack)).
  }
}