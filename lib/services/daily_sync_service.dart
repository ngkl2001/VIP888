// lib/services/daily_sync_service.dart

import 'dart:developer' as developer;

import '../models/ledger_entry.dart';
import '../repositories/daily_data_repository.dart';
import '../repositories/sheets_repository.dart';
import '../providers/daily_data_provider.dart'; // 引入 PendingOperation 和 OperationType
import '../utils/time_utils.dart';
import '../utils/app_logger.dart';


class DailySyncService {
  final DailyDataRepository dailyRepo;
  final SheetsRepository sheetsRepo;

  DailySyncService({
    required this.dailyRepo,
    required this.sheetsRepo,
  });

  /// 執行所有待處理操作（批量同步）
  Future<void> executeBatchSync(List<PendingOperation> operations) async {
    if (operations.isEmpty) return;

    AppLogger.info('DailySyncService', '開始批量同步 ${operations.length} 個操作');

    try {
      final ops = List<PendingOperation>.from(operations); // ✅ 複製一份避免 concurrent modification
      for (final op in operations) {
        switch (op.type) {
          case OperationType.add:
            if (op.entry != null) {
              await sheetsRepo.appendSingleRow(op.entry!.toSheetRow());
            }
            break;
          case OperationType.update:
            if (op.entry != null) {
              final rowNumber = await sheetsRepo.findRowByTimestamp(formatTimestampForSheet(op.entry!.timestamp));
              if (rowNumber != null) {
                await sheetsRepo.updateSingleRow(rowNumber, op.entry!.toSheetRow());
              }
            }
            break;
          case OperationType.delete:
            if (op.timestamp != null) {
              final rowNumber = await sheetsRepo.findRowByTimestamp(
                op.timestamp is DateTime
                  ? formatTimestampForSheet(op.timestamp as DateTime)
                  : formatTimestampForSheet(parseTimestamp(op.timestamp as String))
              );
              if (rowNumber != null) {
                await sheetsRepo.deleteSingleRow(rowNumber);
              }
            }
            break;
        }
      }

      AppLogger.info('DailySyncService', '批量同步完成');
    } catch (e) {
      AppLogger.error('DailySyncService', '批量同步失敗', e);
      rethrow;
    }
  }

  /// 從 Google Sheets 下載資料並覆蓋 SQLite
  Future<bool> fullBidirectionalSync() async {
    try {
      AppLogger.info('DailySyncService', '開始下載 Google Sheets 資料');
      final cloudRows = await sheetsRepo.fetchDataFromSheets();

      if (cloudRows == null || cloudRows.length < 2) {
        AppLogger.warning('DailySyncService', '雲端資料為空或下載失敗');
        return false;
      }

      final List<Map<String, dynamic>> parsedData = [];

      for (int i = 1; i < cloudRows.length; i++) {
        final row = cloudRows[i];
        if (row.isEmpty) continue;

        final rawTimestamp = row[0]?.toString().trim() ?? '';
        if (rawTimestamp.isEmpty) continue;

        try {
          final parsed = parseTimestamp(rawTimestamp);
          final formatted = formatTimestampForSheet(parsed);
          parsedData.add({
            'timestamp': formatted,
            'category': row.length > 1 ? row[1].toString() : '',
            'details': row.length > 2 ? row[2].toString() : '',
            'aed': row.length > 3 ? double.tryParse('${row[3]}') ?? 0.0 : 0.0,
            'usdt': row.length > 4 ? double.tryParse('${row[4]}') ?? 0.0 : 0.0,
            'cny': row.length > 5 ? double.tryParse('${row[5]}') ?? 0.0 : 0.0,
            'online': row.length > 6 ? double.tryParse('${row[6]}') ?? 0.0 : 0.0,
            'edit_note': row.length > 7 ? row[7].toString() : '',
            'last_modified': row.length > 8 ? row[8].toString() : '',
          });
        } catch (e) {
          AppLogger.error('DailySyncService', '無法解析時間: $rawTimestamp', e);
        }
      }

      await dailyRepo.clearAllData();
      AppLogger.info('DailySyncService', '清空 SQLite，準備寫入 ${parsedData.length} 筆');

      /// ✅ 只寫一次
      await dailyRepo.insertBatch(parsedData);
      await sheetsRepo.buildTimestampRowCache(); // ✅ 應該寫在 return 之前

      AppLogger.info('DailySyncService', '雲端資料寫入 SQLite 完成');
      return true;
    } catch (e, stack) {
      AppLogger.error('DailySyncService', '雙向同步失敗', e, stack);
      return false;
    }
  }


  /// 新增資料至本地與雲端
  Future<void> addEntry(LedgerEntry entry) async {
    final map = entry.toMap();
    await dailyRepo.insertData(map);
    await sheetsRepo.appendSingleRow(entry.toSheetRow());
  }

  /// 更新資料
  Future<void> updateEntry(LedgerEntry oldEntry, LedgerEntry newEntry) async {
    final newMap = newEntry.toMap();
    newMap['last_modified'] = formatTimestampForSheet(getDubaiTime());
    await dailyRepo.updateData(newMap);

    int? rowNumber = await findOrRefreshRow(formatTimestampForSheet(oldEntry.timestamp));
    if (rowNumber != null) {
      await sheetsRepo.updateSingleRow(rowNumber, newEntry.toSheetRow());
    } else {
      await sheetsRepo.appendSingleRow(newEntry.toSheetRow());
      AppLogger.warning('DailySyncService', 'fallback append，需人工 review: ${oldEntry.formattedTimestamp}');
    }
    await sheetsRepo.buildTimestampRowCache();
  }


  /// 刪除資料
  Future<void> deleteEntry(String timestamp) async {
    await dailyRepo.deleteByTimestamp(timestamp);
    final rowNumber = await sheetsRepo.findRowByTimestamp(
      formatTimestampForSheet(parseTimestamp(timestamp))
    );
    if (rowNumber != null) {
      await sheetsRepo.deleteRow(rowNumber);
    }
    await checkAndFixConsistency(); // 刪除後自動檢查與修正
  }

  /// 檢查本地與雲端資料筆數是否一致，不一致則自動同步修正
  Future<void> checkAndFixConsistency() async {
    final localCount = await dailyRepo.getDataCount();
    final cloudRows = await sheetsRepo.fetchDataFromSheets();
    final cloudCount = (cloudRows?.length ?? 1) - 1; // 扣掉表頭
    if (localCount != cloudCount) {
      await fullBidirectionalSync();
    }
  }

  /// 杜拜時間
  DateTime getDubaiTime() {
    return DateTime.now().toUtc().add(const Duration(hours: 4));
  }

  /// 過濾與排序資料
  List<LedgerEntry> applyFilters(List<LedgerEntry> entries, {String searchQuery = '', DateTime? startDate, DateTime? endDate}) {
    var filtered = entries;
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered.where((entry) =>
        entry.category.toLowerCase().contains(query) ||
        entry.details.toLowerCase().contains(query) ||
        entry.editNote.toLowerCase().contains(query)
      ).toList();
    }
    if (startDate != null || endDate != null) {
      filtered = filtered.where((entry) {
        final entryDate = entry.timestamp;
        if (startDate != null && entryDate.isBefore(startDate)) return false;
        if (endDate != null && entryDate.isAfter(endDate.add(const Duration(days: 1)))) return false;
        return true;
      }).toList();
    }
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return filtered;
  }

  Future<void> addEntryLocalAndCloud(LedgerEntry entry) async {
    try {
      await dailyRepo.insertData(entry.toMap());
      await sheetsRepo.appendSingleRow(entry.toSheetRow());
    } catch (e, stack) {
      AppLogger.error('DailySyncService', 'addEntryLocalAndCloud error', e, stack);
      rethrow;
    }
  }

  Future<void> updateEntryLocalAndCloud(LedgerEntry oldEntry, LedgerEntry newEntry) async {
    try {
      final newMap = newEntry.toMap();
      newMap['last_modified'] = formatTimestampForSheet(getDubaiTime());
      await dailyRepo.updateData(newMap);
      int? rowNumber = await findOrRefreshRow(formatTimestampForSheet(oldEntry.timestamp));
      if (rowNumber != null) {
        await sheetsRepo.updateSingleRow(rowNumber, newEntry.toSheetRow());
      } else {
        await sheetsRepo.appendSingleRow(newEntry.toSheetRow());
        AppLogger.warning('DailySyncService', 'fallback append，需人工 review: ${oldEntry.formattedTimestamp}');
      }
      await sheetsRepo.buildTimestampRowCache();
    } catch (e, stack) {
      AppLogger.error('DailySyncService', 'updateEntryLocalAndCloud error', e, stack);
      rethrow;
    }
  }

  Future<void> deleteEntryLocalAndCloud(String timestamp) async {
    try {
      await dailyRepo.deleteByTimestamp(timestamp);
      final rowNumber = await sheetsRepo.findRowByTimestamp(
        formatTimestampForSheet(parseTimestamp(timestamp))
      );
      if (rowNumber != null) {
        await sheetsRepo.deleteRow(rowNumber);
      }
      await checkAndFixConsistency();
    } catch (e, stack) {
      AppLogger.error('DailySyncService', 'deleteEntryLocalAndCloud error', e, stack);
      rethrow;
    }
  }

  List<String> getExistingCategories(List<LedgerEntry> entries) {
    final categories = entries.map((e) => e.category).where((cat) => cat.isNotEmpty).toSet().toList();
    categories.sort();
    return categories;
  }

  double calculateTotal(List<LedgerEntry> entries, String field) {
    return entries.fold(0.0, (sum, entry) {
      switch (field) {
        case 'aed':
          return sum + entry.aed;
        case 'usdt':
          return sum + entry.usdt;
        case 'cny':
          return sum + entry.cny;
        case 'online':
          return sum + entry.online;
        default:
          return sum;
      }
    });
  }

  /// 共用 row 查找方法
  Future<int?> findOrRefreshRow(String formattedTimestamp) async {
    int? rowNumber = await sheetsRepo.findRowByTimestamp(formattedTimestamp);
    if (rowNumber == null) {
      await sheetsRepo.buildTimestampRowCache();
      rowNumber = await sheetsRepo.findRowByTimestamp(formattedTimestamp);
    }
    return rowNumber;
  }
}
