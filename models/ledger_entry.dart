/// 帳本記錄數據模型
class LedgerEntry {
  final String timestamp;      // 對應 timestamp_daily
  final String category;
  final String details;
  final String aed;           // 迪拉姆貨幣
  final String usdt;          // USDT 數量
  final String cny;           // 人民幣
  final String online;        // online 貨幣（數字）
  final String lastModified;   // 對應 last_modified
  final String editNote;       // 對應 edit_note

  LedgerEntry({
    required this.timestamp,
    this.category = '',
    this.details = '',
    this.aed = '',
    this.usdt = '',
    this.cny = '',
    this.online = '',
    this.lastModified = '',
    this.editNote = '',
  });

  /// 從數據庫 Map 創建實例
  factory LedgerEntry.fromMap(Map<String, dynamic> map) {
    // 處理數據庫字段名映射
    return LedgerEntry(
      timestamp: map['timestamp_daily'] ?? map['timestamp'] ?? '',
      category: map['category']?.toString() ?? '',
      details: map['details']?.toString() ?? '',
      aed: map['aed']?.toString() ?? '',
      usdt: map['usdt']?.toString() ?? '',
      cny: map['cny']?.toString() ?? '',
      // online 也是數字貨幣
      online: map['online']?.toString() ?? '',
      lastModified: map['last_modified'] ?? map['lastModified'] ?? '',
      editNote: map['edit_note'] ?? map['editNote'] ?? '',
    );
  }

  /// 轉換為數據庫 Map
  Map<String, dynamic> toMap() {
    return {
      'timestamp_daily': timestamp,
      'category': category,
      'details': details,
      'aed': _normalizeNumericValue(aed),
      'usdt': _normalizeNumericValue(usdt),
      'cny': _normalizeNumericValue(cny),
      'online': _normalizeNumericValue(online), // online 也是數字
      'last_modified': lastModified,
      'edit_note': editNote,
    };
  }

  /// 轉換為 Google Sheets 格式
  List<Object?> toSheetRow() {
    return [
      timestamp,
      category,
      details,
      _normalizeNumericValue(aed),    // 確保是數字
      _normalizeNumericValue(usdt),   // 確保是數字
      _normalizeNumericValue(cny),    // 確保是數字
      _normalizeNumericValue(online), // 確保是數字
      editNote,
      lastModified,
    ];
  }

  /// 創建副本並更新指定字段
  LedgerEntry copyWith({
    String? timestamp,
    String? category,
    String? details,
    String? aed,
    String? usdt,
    String? cny,
    String? online,
    String? lastModified,
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

  /// 標準化數值
  static dynamic _normalizeNumericValue(String value) {
    if (value.isEmpty || value == 'null' || value == 'NULL') return 0.0;
    // 處理可能的逗號分隔符
    final cleanValue = value.replaceAll(',', '');
    return double.tryParse(cleanValue) ?? 0.0;
  }
} 