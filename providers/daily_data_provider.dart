//整合本地/雲端，並通知 UI

// lib/providers/daily_data_provider.dart
import 'package:flutter/foundation.dart';
import '../repositories/daily_data_repository.dart';
import '../repositories/sheets_repository.dart';
import '../models/ledger_entry.dart';
import 'dart:developer' as developer;
import 'dart:async';

enum SyncStatus {
  idle,       // 空闲状态
  syncing,    // 同步中
  success,    // 同步成功
  error,      // 同步出错
}

// 操作類型
enum OperationType {
  add,
  update,
  delete,
}

// 操作記錄
class PendingOperation {
  final OperationType type;
  final LedgerEntry? entry;
  final String? timestamp;
  final DateTime createdAt;

  PendingOperation({
    required this.type,
    this.entry,
    this.timestamp,
  }) : createdAt = DateTime.now();
}

class DailyDataProvider extends ChangeNotifier {
  final DailyDataRepository dailyRepo;
  final SheetsRepository sheetsRepo;

  DailyDataProvider({
    required this.dailyRepo,
    required this.sheetsRepo,
  });

  List<Map<String, dynamic>> _dailyList = [];
  List<Map<String, dynamic>> get dailyList => _dailyList;

  // 轉換為 LedgerEntry 列表
  List<LedgerEntry> get entries {
    final list = _dailyList.map((map) => LedgerEntry.fromMap(map)).toList();
    // 按 timestamp 降序排序，最新的在最上面
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  // 篩選後的條目
  List<LedgerEntry> _filteredEntries = [];
  List<LedgerEntry> get filteredEntries => 
      _searchQuery.isEmpty && _startDate == null && _endDate == null
          ? entries 
          : _filteredEntries;

  // 搜索和篩選
  String _searchQuery = '';
  String get searchQuery => _searchQuery;
  
  DateTime? _startDate;
  DateTime? get startDate => _startDate;
  
  DateTime? _endDate;
  DateTime? get endDate => _endDate;

  // 同步狀態
  SyncStatus _syncStatus = SyncStatus.idle;
  SyncStatus get syncStatus => _syncStatus;

  String _syncMessage = '';
  String get syncMessage => _syncMessage;

  // 加載狀態
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _error = '';
  String get error => _error;

  // 樂觀更新追蹤
  final Set<String> _pendingOperations = {};
  final Set<String> _optimisticallyDeleted = {};
  final Set<String> _optimisticallyAdded = {};

  // 🚀 優化：操作隊列
  final List<PendingOperation> _operationQueue = [];
  Timer? _batchSyncTimer;

  // 背景同步定時器
  Timer? _syncTimer;

  /// 初始化
  Future<void> initialize() async {
    await fetchDailyData();
    _startBackgroundSync();
    
    // 初始同步
    fullBidirectionalSync();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _batchSyncTimer?.cancel();
    super.dispose();
  }

  /// 啟動背景同步
  void _startBackgroundSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_pendingOperations.isNotEmpty) {
        fullBidirectionalSync();
      }
    });
  }

  /// 設置同步狀態
  void _setSyncStatus(SyncStatus status, [String message = '']) {
    _syncStatus = status;
    _syncMessage = message;
    notifyListeners();
  }

  /// 清除同步狀態（設為idle）
  void clearSyncStatus() {
    _setSyncStatus(SyncStatus.idle);
  }

  /// 設置搜索查詢
  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
  }

  /// 設置日期範圍
  void setDateRange(DateTime? start, DateTime? end) {
    _startDate = start;
    _endDate = end;
    _applyFilters();
  }

  /// 清除日期篩選
  void clearDateFilter() {
    _startDate = null;
    _endDate = null;
    _applyFilters();
  }

  /// 應用篩選條件
  void _applyFilters() {
    _filteredEntries = entries.where((entry) {
      // 搜索篩選
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesSearch = 
            entry.category.toLowerCase().contains(query) ||
            entry.details.toLowerCase().contains(query) ||
            entry.editNote.toLowerCase().contains(query);
        if (!matchesSearch) return false;
      }

      // 日期篩選
      if (_startDate != null || _endDate != null) {
        try {
          final entryDate = DateTime.parse(entry.timestamp);
          if (_startDate != null && entryDate.isBefore(_startDate!)) return false;
          if (_endDate != null && entryDate.isAfter(_endDate!.add(const Duration(days: 1)))) return false;
        } catch (e) {
          return false;
        }
      }

      return true;
    }).toList();
    
    // 確保篩選後的數據也按時間降序排序（最新的在最上面）
    _filteredEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    notifyListeners();
  }

  /// 獲取現有的類別列表
  List<String> get existingCategories {
    final categories = entries
        .map((e) => e.category)
        .where((cat) => cat.isNotEmpty)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  /// 計算總計
  double get totalAED => _calculateTotal('aed');
  double get totalUSDT => _calculateTotal('usdt');
  double get totalCNY => _calculateTotal('cny');
  double get totalOnline => _calculateTotal('online');

  double _calculateTotal(String field) {
    return filteredEntries.fold(0.0, (sum, entry) {
      String value;
      switch (field) {
        case 'aed':
          value = entry.aed;
          break;
        case 'usdt':
          value = entry.usdt;
          break;
        case 'cny':
          value = entry.cny;
          break;
        case 'online':
          value = entry.online;
          break;
        default:
          value = '0';
      }
      return sum + (double.tryParse(value) ?? 0);
    });
  }

  /// 檢查是否有待處理的操作
  bool get hasPendingOperations => _pendingOperations.isNotEmpty;
  bool get hasPendingDeletes => _optimisticallyDeleted.isNotEmpty;
  bool get hasPendingAdds => _optimisticallyAdded.isNotEmpty;

  bool isPending(String timestamp) => _pendingOperations.contains(timestamp);
  bool isOptimisticallyDeleted(String timestamp) => _optimisticallyDeleted.contains(timestamp);
  bool isOptimisticallyAdded(String timestamp) => _optimisticallyAdded.contains(timestamp);

  /// 從本地資料庫取得所有 daily_data
  Future<void> fetchDailyData() async {
    try {
      _isLoading = true;
      _error = '';
      notifyListeners();

      final data = await dailyRepo.getAllData();
      _dailyList = List<Map<String, dynamic>>.from(data);
      _applyFilters();
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = '載入資料失敗: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 刷新數據
  Future<void> refresh() async {
    await fetchDailyData();
    await fullBidirectionalSync();
  }

  /// 🚀 優化：將操作加入隊列並延遲批量同步
  void _queueOperation(PendingOperation operation) {
    _operationQueue.add(operation);
    
    // 取消之前的定時器
    _batchSyncTimer?.cancel();
    
    // 設置新的定時器，2秒後執行批量同步
    _batchSyncTimer = Timer(const Duration(seconds: 2), () {
      _executeBatchSync();
    });
  }

  /// 🚀 優化：執行批量同步
  Future<void> _executeBatchSync() async {
    if (_operationQueue.isEmpty) return;
    
    developer.log('🚀 開始批量同步 ${_operationQueue.length} 個操作');
    
    // 複製隊列並清空
    final operations = List<PendingOperation>.from(_operationQueue);
    _operationQueue.clear();
    
    try {
      for (final op in operations) {
        switch (op.type) {
          case OperationType.add:
            if (op.entry != null) {
              await sheetsRepo.appendSingleRow(op.entry!.toSheetRow());
            }
            break;
          case OperationType.update:
            if (op.entry != null) {
              final rowNumber = await sheetsRepo.findRowByTimestamp(op.entry!.timestamp);
              if (rowNumber != null) {
                await sheetsRepo.updateSingleRow(rowNumber, op.entry!.toSheetRow());
              }
            }
            break;
          case OperationType.delete:
            if (op.timestamp != null) {
              final rowNumber = await sheetsRepo.findRowByTimestamp(op.timestamp!);
              if (rowNumber != null) {
                await sheetsRepo.deleteSingleRow(rowNumber);
              }
            }
            break;
        }
      }
      
      developer.log('✅ 批量同步完成');
    } catch (e) {
      developer.log('❌ 批量同步失敗: $e');
      // 失敗的操作重新加入隊列
      _operationQueue.addAll(operations);
    }
  }

  /// 新增一筆資料（樂觀更新）
  Future<void> addEntry(LedgerEntry entry) async {
    developer.log('🚀 Provider.addEntry 開始: ${entry.timestamp}');
    
    // 樂觀更新 UI
    _optimisticallyAdded.add(entry.timestamp);
    _pendingOperations.add(entry.timestamp);
    
    final map = entry.toMap();
    _dailyList.add(map);
    _applyFilters();
    notifyListeners();

    try {
      // 存儲到本地
      await dailyRepo.insertData(map);
      
      // 🚀 優化：使用單行追加而不是全表更新
      await sheetsRepo.appendSingleRow(entry.toSheetRow());
      
      // 成功後移除標記
      _optimisticallyAdded.remove(entry.timestamp);
      _pendingOperations.remove(entry.timestamp);
      notifyListeners();
      
      developer.log('✅ Provider.addEntry 成功');
    } catch (e) {
      // 失敗時回滾
      _dailyList.removeWhere((item) => item['timestamp_daily'] == entry.timestamp);
      _optimisticallyAdded.remove(entry.timestamp);
      _pendingOperations.remove(entry.timestamp);
      
      // 🚀 優化：失敗時加入重試隊列
      _queueOperation(PendingOperation(type: OperationType.add, entry: entry));
      
      _applyFilters();
      notifyListeners();
      
      developer.log('❌ Provider.addEntry 失敗，已加入重試隊列: $e');
    }
  }

  /// 更新一筆資料（樂觀更新）
  Future<void> updateEntry(LedgerEntry oldEntry, LedgerEntry newEntry) async {
    developer.log('🔄 Provider.updateEntry 開始');
    
    // 樂觀更新 UI
    _pendingOperations.add(oldEntry.timestamp);
    
    final index = _dailyList.indexWhere(
      (item) => item['timestamp_daily'] == oldEntry.timestamp
    );
    
    if (index == -1) {
      throw Exception('找不到要更新的記錄');
    }
    
    final oldData = Map<String, dynamic>.from(_dailyList[index]);
    _dailyList[index] = newEntry.toMap();
    _applyFilters();
    notifyListeners();

    try {
      // 更新本地
      await dailyRepo.updateData(newEntry.toMap());
      
      // 🚀 優化：只更新單行
      final rowNumber = await sheetsRepo.findRowByTimestamp(oldEntry.timestamp);
      if (rowNumber != null) {
        await sheetsRepo.updateSingleRow(rowNumber, newEntry.toSheetRow());
      } else {
        // 如果找不到，可能需要新增
        await sheetsRepo.appendSingleRow(newEntry.toSheetRow());
      }
      
      // 成功後移除標記
      _pendingOperations.remove(oldEntry.timestamp);
      notifyListeners();
      
      developer.log('✅ Provider.updateEntry 成功');
    } catch (e) {
      // 失敗時回滾
      _dailyList[index] = oldData;
      _pendingOperations.remove(oldEntry.timestamp);
      
      // 🚀 優化：失敗時加入重試隊列
      _queueOperation(PendingOperation(type: OperationType.update, entry: newEntry));
      
      _applyFilters();
      notifyListeners();
      
      developer.log('❌ Provider.updateEntry 失敗，已加入重試隊列: $e');
    }
  }

  /// 刪除一筆資料（樂觀更新）
  Future<void> deleteEntry(String timestamp) async {
    developer.log('🗑️ Provider.deleteEntry 開始: $timestamp');
    
    // 樂觀更新 UI
    _optimisticallyDeleted.add(timestamp);
    _pendingOperations.add(timestamp);
    notifyListeners();

    try {
      // 從本地刪除
      await dailyRepo.deleteByTimestamp(timestamp);
      
      // 🚀 優化：只刪除單行
      final rowNumber = await sheetsRepo.findRowByTimestamp(timestamp);
      if (rowNumber != null) {
        await sheetsRepo.deleteSingleRow(rowNumber);
      }
      
      // 成功後從列表移除
      _dailyList.removeWhere((item) => item['timestamp_daily'] == timestamp);
      _optimisticallyDeleted.remove(timestamp);
      _pendingOperations.remove(timestamp);
      _applyFilters();
      notifyListeners();
      
      developer.log('✅ Provider.deleteEntry 成功');
    } catch (e) {
      // 失敗時恢復顯示
      _optimisticallyDeleted.remove(timestamp);
      _pendingOperations.remove(timestamp);
      
      // 🚀 優化：失敗時加入重試隊列
      _queueOperation(PendingOperation(type: OperationType.delete, timestamp: timestamp));
      
      notifyListeners();
      
      developer.log('❌ Provider.deleteEntry 失敗，已加入重試隊列: $e');
    }
  }

  /// 強制同步所有待處理操作
  Future<void> forceSyncAll() async {
    // 先執行批量同步
    await _executeBatchSync();
    // 再執行完整同步
    await fullBidirectionalSync();
  }

  /// 新增一筆資料到本地資料庫
  Future<void> addDailyRecord(Map<String, dynamic> record) async {
    final entry = LedgerEntry.fromMap(record);
    await addEntry(entry);
  }

  /// 完整的雙向同步：雲端 <-> 本地
  Future<bool> fullBidirectionalSync() async {
    _setSyncStatus(SyncStatus.syncing, '開始同步數據...');
    
    try {
      // 1. 獲取雲端數據
      _setSyncStatus(SyncStatus.syncing, '正在從雲端下載數據...');
      final cloudRows = await sheetsRepo.fetchDataFromSheets();
      
      if (cloudRows == null || cloudRows.isEmpty) {
        _setSyncStatus(SyncStatus.error, '雲端數據為空或無法連接');
        return false;
      }

      // 2. 解析雲端數據為Map格式
      final Map<String, Map<String, dynamic>> cloudDataMap = {};
      for (int i = 1; i < cloudRows.length; i++) {
        final row = cloudRows[i];
        if (row.isEmpty) continue;
        
        final timestamp = row[0].toString();
        if (timestamp.isEmpty) continue;

        cloudDataMap[timestamp] = {
          'timestamp_daily': timestamp,
          'category': (row.length > 1) ? row[1].toString() : '',
          'details': (row.length > 2) ? row[2].toString() : '',
          'aed': (row.length > 3) ? double.tryParse('${row[3]}') ?? 0.0 : 0.0,
          'usdt': (row.length > 4) ? double.tryParse('${row[4]}') ?? 0.0 : 0.0,
          'cny': (row.length > 5) ? double.tryParse('${row[5]}') ?? 0.0 : 0.0,
          'online': (row.length > 6) ? double.tryParse('${row[6]}') ?? 0.0 : 0.0,
          'edit_note': (row.length > 7) ? row[7].toString() : '',
          'last_modified': (row.length > 8) ? row[8].toString() : '',
        };
      }

      // 3. 獲取本地數據
      _setSyncStatus(SyncStatus.syncing, '正在讀取本地數據...');
      final localData = await dailyRepo.getAllData();
      final Map<String, Map<String, dynamic>> localDataMap = {};
      for (final item in localData) {
        final timestamp = item['timestamp_daily']?.toString() ?? '';
        if (timestamp.isNotEmpty) {
          localDataMap[timestamp] = item;
        }
      }

      // 4. 對比和同步邏輯
      _setSyncStatus(SyncStatus.syncing, '正在對比數據差異...');
      
      // 4a. 處理雲端數據到本地
      int cloudToLocalCount = 0;
      for (final cloudTimestamp in cloudDataMap.keys) {
        final cloudData = cloudDataMap[cloudTimestamp]!;
        final localData = localDataMap[cloudTimestamp];

        if (localData == null) {
          // 雲端有但本地沒有 -> 插入到本地
          await dailyRepo.insertData(cloudData);
          cloudToLocalCount++;
        } else {
          // 都有數據，比較last_modified時間
          final cloudModified = cloudData['last_modified']?.toString() ?? '';
          final localModified = localData['last_modified']?.toString() ?? '';
          
          // 如果雲端更新或本地沒有修改時間，更新本地
          if (cloudModified.compareTo(localModified) > 0 || localModified.isEmpty) {
            await dailyRepo.updateData(cloudData);
            cloudToLocalCount++;
          }
        }
      }

      // 4b. 處理本地數據到雲端（將本地獨有的數據上傳）
      final List<String> localOnlyTimestamps = [];
      for (final localTimestamp in localDataMap.keys) {
        if (!cloudDataMap.containsKey(localTimestamp)) {
          localOnlyTimestamps.add(localTimestamp);
        }
      }

      // 4c. 刪除本地有但雲端已刪除的數據
      for (final localTimestamp in localDataMap.keys) {
        if (!cloudDataMap.containsKey(localTimestamp)) {
          // 這裡可以選擇刪除或上傳，現在選擇上傳到雲端
          // await dailyRepo.deleteByTimestamp(localTimestamp);
        }
      }

      // 5. 如果有本地獨有的數據，上傳到雲端
      if (localOnlyTimestamps.isNotEmpty) {
        _setSyncStatus(SyncStatus.syncing, '正在上傳本地獨有數據到雲端...');
        await _uploadLocalDataToSheets(localOnlyTimestamps, localDataMap);
      }

      // 6. 更新本地顯示數據
      await fetchDailyData();

      _setSyncStatus(SyncStatus.success, 
        '同步完成！雲端→本地: $cloudToLocalCount 筆，本地→雲端: ${localOnlyTimestamps.length} 筆');
      
      developer.log('同步完成：雲端→本地 $cloudToLocalCount 筆，本地→雲端 ${localOnlyTimestamps.length} 筆');
      return true;

    } catch (e) {
      developer.log('同步失敗: $e', name: 'DailyDataProvider');
      _setSyncStatus(SyncStatus.error, '同步失敗: ${e.toString()}');
      return false;
    }
  }

  /// 上傳本地獨有數據到雲端
  Future<void> _uploadLocalDataToSheets(
    List<String> timestamps, 
    Map<String, Map<String, dynamic>> localDataMap
  ) async {
    // 獲取當前雲端所有數據
    final cloudRows = await sheetsRepo.fetchDataFromSheets() ?? [];
    
    // 創建新的數據陣列
    final newRows = <List<Object?>>[];
    
    // 添加標頭
    newRows.add([
      'timestamp_daily',
      'category', 
      'details',
      'aed',
      'usdt',
      'cny',
      'online',
      'edit_note',
      'last_modified',
    ]);

    // 添加原有雲端數據
    for (int i = 1; i < cloudRows.length; i++) {
      newRows.add(cloudRows[i]);
    }

    // 添加本地獨有數據
    for (final timestamp in timestamps) {
      final data = localDataMap[timestamp]!;
      newRows.add([
        data['timestamp_daily'] ?? '',
        data['category'] ?? '',
        data['details'] ?? '',
        data['aed'] ?? 0.0,
        data['usdt'] ?? 0.0,
        data['cny'] ?? 0.0,
        data['online'] ?? 0.0,
        data['edit_note'] ?? '',
        data['last_modified'] ?? '',
      ]);
    }

    // 寫入雲端
    await sheetsRepo.writeDataToSheets(newRows);
  }

  /// 舊版方法保持向後兼容
  @Deprecated('請使用 fullBidirectionalSync() 方法')
  Future<void> fetchFromSheets() async {
    await fullBidirectionalSync();
  }

  /// 舊版方法保持向後兼容  
  @Deprecated('請使用 fullBidirectionalSync() 方法')
  Future<void> syncToSheets() async {
    await fullBidirectionalSync();
  }
}
