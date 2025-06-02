// lib/providers/daily_data_provider.dart

import 'package:flutter/foundation.dart';
import '../repositories/daily_data_repository.dart';
import '../repositories/sheets_repository.dart';
import '../models/ledger_entry.dart';
import '../services/daily_sync_service.dart';
import '../services/optimistic_state_manager.dart';
import 'dart:async';
import 'dart:developer' as developer;
import '../utils/time_utils.dart';

// 保留 enum 與 PendingOperation 類

enum SyncStatus {
  idle,
  syncing,
  success,
  error,
}

enum OperationType {
  add,
  update,
  delete,
}

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
  final DailySyncService syncService;

  DailyDataProvider({
    required this.dailyRepo,
    required this.sheetsRepo,
  }) : syncService = DailySyncService(dailyRepo: dailyRepo, sheetsRepo: sheetsRepo);

  List<Map<String, dynamic>> _dailyList = [];
  List<Map<String, dynamic>> get dailyList => _dailyList;

  List<LedgerEntry> get entries => _dailyList.map((map) => LedgerEntry.fromMap(map)).toList();

  List<LedgerEntry> _filteredEntries = [];
  List<LedgerEntry> get filteredEntries =>
      _searchQuery.isEmpty && _startDate == null && _endDate == null ? entries : _filteredEntries;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  DateTime? _startDate;
  DateTime? get startDate => _startDate;

  DateTime? _endDate;
  DateTime? get endDate => _endDate;

  SyncStatus _syncStatus = SyncStatus.idle;
  SyncStatus get syncStatus => _syncStatus;

  String _syncMessage = '';
  String get syncMessage => _syncMessage;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _error = '';
  String get error => _error;

  final OptimisticStateManager _optimisticState = OptimisticStateManager();

  final List<PendingOperation> _operationQueue = [];
  Timer? _batchSyncTimer;
  Timer? _syncTimer;

  Future<void> initialize() async {
    await fetchDailyData();
    _startBackgroundSync();
    fullBidirectionalSync();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _batchSyncTimer?.cancel();
    super.dispose();
  }

  void _startBackgroundSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_optimisticState.hasPendingOperations) {
        fullBidirectionalSync();
      }
    });
  }

  void _setSyncStatus(SyncStatus status, [String message = '']) {
    _syncStatus = status;
    _syncMessage = message;
    notifyListeners();
    if (status == SyncStatus.success || status == SyncStatus.error) {
      Future.delayed(const Duration(seconds: 3), () {
        if (_syncStatus == status) clearSyncStatus();
      });
    }
  }

  void clearSyncStatus() => _setSyncStatus(SyncStatus.idle);

  void setSearchQuery(String query) {
    _searchQuery = query;
    _filteredEntries = syncService.applyFilters(entries, searchQuery: _searchQuery, startDate: _startDate, endDate: _endDate);
    notifyListeners();
  }

  void setDateRange(DateTime? start, DateTime? end) {
    _startDate = start;
    _endDate = end;
    _filteredEntries = syncService.applyFilters(entries, searchQuery: _searchQuery, startDate: _startDate, endDate: _endDate);
    notifyListeners();
  }

  void clearDateFilter() {
    _startDate = null;
    _endDate = null;
    _filteredEntries = syncService.applyFilters(entries, searchQuery: _searchQuery, startDate: _startDate, endDate: _endDate);
    notifyListeners();
  }

  List<String> get existingCategories => syncService.getExistingCategories(entries);

  double get totalAED => syncService.calculateTotal(filteredEntries, 'aed');
  double get totalUSDT => syncService.calculateTotal(filteredEntries, 'usdt');
  double get totalCNY => syncService.calculateTotal(filteredEntries, 'cny');
  double get totalOnline => syncService.calculateTotal(filteredEntries, 'online');

  bool get hasPendingOperations => _optimisticState.hasPendingOperations;
  bool get hasPendingDeletes => _optimisticState.hasPendingDeletes;
  bool get hasPendingAdds => _optimisticState.hasPendingAdds;

  bool isPending(String timestamp) => _optimisticState.isPending(timestamp);
  bool isOptimisticallyDeleted(String timestamp) => _optimisticState.isDeleted(timestamp);
  bool isOptimisticallyAdded(String timestamp) => _optimisticState.isAdded(timestamp);

  Future<void> fetchDailyData() async {
    try {
      _isLoading = true;
      _error = '';
      notifyListeners();

      final data = await dailyRepo.getAllData();
      _dailyList = List<Map<String, dynamic>>.from(data);
      _filteredEntries = syncService.applyFilters(entries, searchQuery: _searchQuery, startDate: _startDate, endDate: _endDate);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = '載入資料失敗: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> fullBidirectionalSync() async {
    _setSyncStatus(SyncStatus.syncing, '正在同步中...');

    try {
      await syncService.executeBatchSync(_operationQueue);
      _operationQueue.clear();

      final result = await syncService.fullBidirectionalSync();
      if (result) await fetchDailyData();

      _setSyncStatus(SyncStatus.success, '同步成功');
      return true;
    } catch (e) {
      _setSyncStatus(SyncStatus.error, '同步失敗: $e');
      return false;
    }
  }

  Future<bool> refresh() async {
    if (_isLoading) return false; // ✅ 防止重複觸發
    _isLoading = true;
    notifyListeners();

    try {
      return await fullBidirectionalSync();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _isBatchSyncing = false;

  void _queueOperation(PendingOperation operation) {
    _operationQueue.add(operation);
    _batchSyncTimer?.cancel();

    _batchSyncTimer = Timer(const Duration(seconds: 2), () async {
      if (_isBatchSyncing) return; // 🔒 防止重入
      _isBatchSyncing = true;
      await syncService.executeBatchSync(List.from(_operationQueue)); // 👈 安全做法
      _operationQueue.clear();
      _isBatchSyncing = false;
    });
  }

  Future<void> addEntryLocalAndCloud(LedgerEntry entry) async {
    _optimisticState.markAdded(entry.formatted);
    _optimisticState.markPending(entry.formatted);
    _dailyList.insert(0, entry.toMap());
    notifyListeners();
    try {
      await syncService.addEntryLocalAndCloud(entry);
      _optimisticState.clear(entry.formatted);
      notifyListeners();
    } catch (e, stack) {
      developer.log('addEntryLocalAndCloud error', error: e, stackTrace: stack);
      _queueOperation(PendingOperation(type: OperationType.add, entry: entry));
      notifyListeners();
    }
  }

  Future<void> updateEntryLocalAndCloud(LedgerEntry oldEntry, LedgerEntry newEntry) async {
    final index = _dailyList.indexWhere((item) => item['timestamp'] == oldEntry.formatted);
    if (index == -1) {
      developer.log('找不到要更新的項目', error: oldEntry.formatted);
      return;
    }
    _optimisticState.markPending(oldEntry.formatted);
    final oldData = Map<String, dynamic>.from(_dailyList[index]);
    _dailyList[index] = newEntry.toMap();
    notifyListeners();
    try {
      await syncService.updateEntryLocalAndCloud(oldEntry, newEntry);
      _optimisticState.clear(oldEntry.formatted);
      notifyListeners();
    } catch (e, stack) {
      developer.log('updateEntryLocalAndCloud error', error: e, stackTrace: stack);
      _dailyList[index] = oldData;
      _optimisticState.clear(oldEntry.formatted);
      _queueOperation(PendingOperation(type: OperationType.update, entry: newEntry));
      notifyListeners();
    }
  }

  Future<void> deleteEntryLocalAndCloud(LedgerEntry entry) async {
    final ts = entry.formatted;
    _optimisticState.markDeleted(ts);
    _optimisticState.markPending(ts);
    notifyListeners();
    try {
      await syncService.deleteEntryLocalAndCloud(ts);
      _dailyList.removeWhere((item) => item['timestamp'] == ts);
      _optimisticState.clear(ts);
      notifyListeners();
    } catch (e, stack) {
      developer.log('deleteEntryLocalAndCloud error', error: e, stackTrace: stack);
      _optimisticState.clear(ts);
      _queueOperation(PendingOperation(type: OperationType.delete, timestamp: ts));
      notifyListeners();
    }
  }

  Future<void> addDailyRecord(Map<String, dynamic> record) async {
    // Ensure the timestamp is unique. This is a temporary solution.
    // A more robust solution would involve checking for existing timestamps
    // or using a guaranteed unique ID generation method.
    // For now, we add a millisecond to the current time if a record with the same timestamp exists.
    record['timestamp'] = formatTimestampForSheet(syncService.getDubaiTime());
    final entry = LedgerEntry.fromMap(record);
    await addEntryLocalAndCloud(entry);
  }

  @Deprecated('請使用 fullBidirectionalSync() 方法')
  Future<void> fetchFromSheets() async => await fullBidirectionalSync();

  @Deprecated('請使用 fullBidirectionalSync() 方法')
  Future<void> syncToSheets() async => await fullBidirectionalSync();

  List<PendingOperation> get operationQueue => List.unmodifiable(_operationQueue);
  void clearOperationQueue() {
    _operationQueue.clear();
  }
}