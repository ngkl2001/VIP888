import 'package:intl/intl.dart';

const String kTimestampFormat = 'dd/MM/yyyy HH:mm:ss';

/// 容錯解析 timestamp，支援多種常見格式，預設 dd/MM/yyyy HH:mm:ss
DateTime parseTimestamp(String input) {
  final formats = [
    DateFormat(kTimestampFormat, 'en_US'),
    DateFormat('yyyy-MM-dd HH:mm:ss', 'en_US'),
    DateFormat('yyyy-MM-dd HH:mm', 'en_US'),
    DateFormat('yyyy-MM-dd', 'en_US'),
  ];
  for (final fmt in formats) {
    try {
      return fmt.parseStrict(input);
    } catch (_) {}
  }
  // 最後嘗試 ISO 8601
  try {
    return DateTime.parse(input);
  } catch (_) {}
  throw FormatException('無法解析時間格式: $input');
}

/// 統一格式化 timestamp 寫入（所有資料流都用這個）
String formatTimestamp(DateTime dt) {
  return formatTimestampForSheet(dt);
}

/// 將 DateTime 轉為儲存在 Google Sheets 的格式
String formatTimestampForSheet(DateTime dt) {
  return DateFormat(kTimestampFormat, 'en_US').format(dt);
}

/// 將 DateTime 格式化為 UI 顯示格式
String formatTimestampForDisplay(DateTime dt) {
  return DateFormat('yyyy-MM-dd HH:mm').format(dt);
}

/// 將 DateTime 格式化為短日期格式
String formatTimestampShort(DateTime dt) {
  return DateFormat('yyyy-MM-dd').format(dt);
}

extension DateTimeFormatExt on DateTime {
  String get formattedTimestamp => formatTimestampForDisplay(this);
}
