import '../utils/time_utils.dart';

/// 帳本記錄數據模型
class LedgerEntry {
  final DateTime timestamp;
  final String category;
  final String details;
  final double aed;
  final double usdt;
  final double cny;
  final double online;
  final DateTime lastModified;
  final String editNote;

  /// 格式化為標準顯示格式
  String get formatted => formatTimestampForSheet(timestamp);
  
  /// 格式化為資料庫格式
  String get formattedDb => formatTimestampForSheet(timestamp);
  
  /// 格式化為顯示格式（與 formatted 相同）
  String get formattedTimestamp => formatTimestampForDisplay(timestamp);

  LedgerEntry({
    required this.timestamp,
    this.category = '',
    this.details = '',
    this.aed = 0.0,
    this.usdt = 0.0,
    this.cny = 0.0,
    this.online = 0.0,
    DateTime? lastModified,
    this.editNote = '',
  }) : lastModified = lastModified ?? DateTime.now();

  /// 從數據庫 Map 創建實例
  factory LedgerEntry.fromMap(Map<String, dynamic> map) => LedgerEntry.fromDbMap(map);

  /// 從 SQLite Map 創建實例
  factory LedgerEntry.fromDbMap(Map<String, dynamic> map) {
    final raw = map['timestamp'];
    return LedgerEntry(
      timestamp: parseTimestamp(raw),
      category: map['category']?.toString() ?? '',
      details: map['details']?.toString() ?? '',
      aed: double.tryParse(map['aed']?.toString() ?? '') ?? 0.0,
      usdt: double.tryParse(map['usdt']?.toString() ?? '') ?? 0.0,
      cny: double.tryParse(map['cny']?.toString() ?? '') ?? 0.0,
      online: double.tryParse(map['online']?.toString() ?? '') ?? 0.0,
      lastModified: map['last_modified'] != null ? parseTimestamp(map['last_modified']) : DateTime.now(),
      editNote: map['edit_note'] ?? map['editNote'] ?? '',
    );
  }

  /// 從 Google Sheets 列資料創建實例
  factory LedgerEntry.fromSheetRow(List<Object?> row) {
    return LedgerEntry(
      timestamp: parseTimestamp(row[0]?.toString() ?? ''),
      category: row.length > 1 ? row[1].toString() : '',
      details: row.length > 2 ? row[2].toString() : '',
      aed: row.length > 3 ? double.tryParse(row[3]?.toString() ?? '') ?? 0.0 : 0.0,
      usdt: row.length > 4 ? double.tryParse(row[4]?.toString() ?? '') ?? 0.0 : 0.0,
      cny: row.length > 5 ? double.tryParse(row[5]?.toString() ?? '') ?? 0.0 : 0.0,
      online: row.length > 6 ? double.tryParse(row[6]?.toString() ?? '') ?? 0.0 : 0.0,
      editNote: row.length > 7 ? row[7].toString() : '',
      lastModified: row.length > 8 && row[8] != null && row[8].toString().isNotEmpty
          ? parseTimestamp(row[8].toString())
          : DateTime.now(),
    );
  }

  /// 轉換為數據庫 Map
  Map<String, dynamic> toMap() {
    return {
      'timestamp': formatTimestampForSheet(timestamp),
      'category': category,
      'details': details,
      'aed': aed,
      'usdt': usdt,
      'cny': cny,
      'online': online,
      'last_modified': formatTimestampForSheet(lastModified),
      'edit_note': editNote,
    };
  }

  /// 轉換為 Google Sheets 格式
  List<Object?> toSheetRow() {
    return [
      formatTimestampForSheet(timestamp),
      category,
      details,
      aed,
      usdt,
      cny,
      online,
      editNote,
      formatTimestampForSheet(lastModified),
    ];
  }

  /// 創建副本並更新指定字段
  LedgerEntry copyWith({
    DateTime? timestamp,
    String? category,
    String? details,
    double? aed,
    double? usdt,
    double? cny,
    double? online,
    DateTime? lastModified,
    String? editNote,
  }) {
    return LedgerEntry(
      timestamp: timestamp ?? this.timestamp,
      category: category ?? this.category,
      details: details ?? this.details,
      aed: aed ?? this.aed,
      usdt: usdt ?? this.usdt,
      cny: cny ?? this.cny,
      online: online ?? this.online,
      lastModified: lastModified ?? this.lastModified,
      editNote: editNote ?? this.editNote,
    );
  }
}
