import 'dart:developer' as developer;

class AppLogger {
  static void info(String module, String message) {
    developer.log('[✅ $module] $message');
  }

  static void warning(String module, String message) {
    developer.log('[⚠️ $module] $message');
  }

  static void error(String module, String message, [dynamic error, StackTrace? stack]) {
    developer.log('[❌ $module] $message', error: error, stackTrace: stack);
  }

  static void debug(String module, String message) {
    developer.log('[🔍 $module] $message');
  }
} 