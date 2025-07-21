import 'dart:io';

enum LogLevel { none, error, warning, info, debug }

class Log {
  static LogLevel _level = LogLevel.debug;

  static LogLevel get level => _level;
  static set level(LogLevel value) => _level = value;

  static void error(Function messageBuilder) {
    if (level.index >= LogLevel.error.index) {
      stderr.writeln('[ERROR] ${messageBuilder()}');
    }
  }

  static void warn(Function messageBuilder) {
    if (level.index >= LogLevel.warning.index) {
      print('[WARN] ${messageBuilder()}');
    }
  }

  static void info(Function messageBuilder) {
    if (level.index >= LogLevel.info.index) {
      print('[INFO] ${messageBuilder()}');
    }
  }

  static void debug(Function messageBuilder) {
    if (level.index >= LogLevel.debug.index) {
      print('[DEBUG] ${messageBuilder()}');
    }
  }

}