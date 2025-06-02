//Google Sheets API 存取

// lib/repositories/sheets_repository.dart

import 'package:googleapis/sheets/v4.dart' as sheets;
// 注意：我們需要 'auth_io.dart' 裡的 clientViaServiceAccount
import 'package:googleapis_auth/auth_io.dart';

// 新增：要用 rootBundle，就要 import
import 'package:flutter/services.dart' show rootBundle;
// 如果要解析 JSON，還需要 dart:convert
import 'dart:convert';

/// 負責跟 Google Sheets 通訊的邏輯
class SheetsRepository {

  /// 你的 Google 試算表 ID，可從網址中取得
  final String spreadsheetId;

  /// Service Account JSON 檔的絕對路徑或 assets 路徑
  final String serviceAccountJsonPath;

  /// 要操作的範圍 (如 "daily!A1:I")
  final String range;
  final List<String>? header; // ✅ 支援外部自訂欄位名稱

  sheets.SheetsApi? _sheetsApi;

  SheetsRepository({
    required this.spreadsheetId,
    required this.serviceAccountJsonPath,
    required this.range,
    this.header, // ✅ 新增

  });

  Future<void> buildTimestampRowCache() async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized. Call initSheetsApi() first.');
    }

    final response = await _sheetsApi!.spreadsheets.values.get(
      spreadsheetId,
      '${range.split('!')[0]}!A:A',
    );

    final values = response.values;
    if (values == null) {
      _timestampToRowCache = {};
      return;
    }

    final Map<String, int> cache = {};
    for (int i = 1; i < values.length; i++) {
      if (values[i].isNotEmpty) {
        final ts = values[i][0].toString().trim();
        cache[ts] = i + 1; // 因為 Sheets 是 1-based row index
      }
    }

    _timestampToRowCache = cache;
  }



  /// 初始化 Google Sheets API (Service Account 模式)
  Future<void> initSheetsApi() async {
    // 改：使用 rootBundle 讀 assets 中的檔案
    final credentialsBytes = await rootBundle.load(serviceAccountJsonPath);
    // 轉成可讀字串
    final credentialsString = utf8.decode(credentialsBytes.buffer.asUint8List());

    // 需要的 scope: Spreadsheets 讀寫
    final scopes = [sheets.SheetsApi.spreadsheetsScope];

    // 用 JSON 字串初始化 ServiceAccountCredentials
    final client = await clientViaServiceAccount(
      ServiceAccountCredentials.fromJson(json.decode(credentialsString)),
      scopes,
    );

    // 建立 SheetsApi 實例
    _sheetsApi = sheets.SheetsApi(client);
  }

  /// 從 Google Sheets 取得資料
  /// 回傳二維陣列，每個 row 都是一個 List<Object?>。
  /// rows[0] 通常是標頭，rows[1..n] 才是真正資料。
  Future<List<List<Object?>>?> fetchDataFromSheets() async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized. Call initSheetsApi() first.');
    }

    final response = await _sheetsApi!.spreadsheets.values.get(
      spreadsheetId,
      range,
    );

    return response.values; // 二維陣列 (List<List<Object?>>)
  }

  /// 將資料 (rows) 覆蓋寫入到 Google Sheets
  /// [rows] 是一個二維陣列，每個元素是一個 List<Object?> 代表一列
  /// 例如: [
  ///   ['timestamp', 'category', 'details', 'aed', 'usdt', 'cny', 'online', 'edit_note', 'last_modified'],
  ///   ['2023-06-01T12:00:00Z', 'Food', 'Lunch details', 10.0, 5.0, 50.0, 'Yes', 'Note', '2023-06-01T12:01:00Z'],
  ///   ...
  /// ]
  Future<void> writeDataToSheets(List<List<Object?>> rows) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized. Call initSheetsApi() first.');
    }

    final valueRange = sheets.ValueRange(
      values: rows,
    );

    // RAW = 直接寫入原值 ; USER_ENTERED = 依照使用者格式 (例如公式).
    await _sheetsApi!.spreadsheets.values.update(
      valueRange,
      spreadsheetId,
      range,
      valueInputOption: 'USER_ENTERED',
    );
  }

  // ========== 🚀 優化：單行操作方法 ==========
  
  /// 追加單行數據到表格末尾（優化版本）
  Future<void> appendSingleRow(List<Object?> row) async {

    final headerRow = header ?? [
      'timestamp', 'category', 'details', 'aed',
      'usdt', 'cny', 'online', 'edit_note', 'last_modified'
    ];

    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized. Call initSheetsApi() first.');
    }

    // 🚀 修改：插入到第2行（表頭下面），而不是追加到最後
    // 先獲取現有數據
    final response = await _sheetsApi!.spreadsheets.values.get(
      spreadsheetId,
      range,
    );

    final existingRows = response.values ?? [];
    if (existingRows.isEmpty) {
      // 如果沒有數據，使用外部指定的 header 或預設值
      final headerRow = header ?? [
        'timestamp', 'category', 'details', 'aed',
        'usdt', 'cny', 'online', 'edit_note', 'last_modified'
      ];
      await writeDataToSheets([headerRow, row]);
      return;
    }


    // 構建新的數據：表頭 + 新行 + 原有數據（除表頭外）
    final newRows = <List<Object?>>[];
    newRows.add(existingRows[0]); // 保留表頭
    newRows.add(row); // 新數據插入到第2行
    
    // 添加原有數據（跳過表頭）
    for (int i = 1; i < existingRows.length; i++) {
      if (existingRows[i].isNotEmpty) {
        newRows.add(existingRows[i]);
      }
    }

    // 寫回整個表格
    await writeDataToSheets(newRows);
  }

  /// 根據 timestamp 查找行號（1-based index）
  Map<String, int>? _timestampToRowCache; // 加在 class SheetsRepository 中頂部

  Future<int?> findRowByTimestamp(String timestamp) async {
    if (_timestampToRowCache == null || !_timestampToRowCache!.containsKey(timestamp)) {
      await buildTimestampRowCache();
    }
    return _timestampToRowCache![timestamp];
  }



  /// 更新特定行的數據（優化版本）
  Future<void> updateSingleRow(int rowNumber, List<Object?> row) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized. Call initSheetsApi() first.');
    }

    final valueRange = sheets.ValueRange(
      values: [row],
    );

    // 構建特定行的範圍，例如 "daily!A5:I5"
    final sheetName = range.split('!')[0];
    final updateRange = '$sheetName!A$rowNumber:I$rowNumber';

    await _sheetsApi!.spreadsheets.values.update(
      valueRange,
      spreadsheetId,
      updateRange,
      valueInputOption: 'USER_ENTERED',
    );
  }

  /// 刪除特定行（通過清空內容）
  Future<void> deleteSingleRow(int rowNumber) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized. Call initSheetsApi() first.');
    }

    // Google Sheets API 不直接支持刪除行，我們清空該行內容
    final emptyRow = List<Object?>.filled(9, ''); // 9 個空字符串
    await updateSingleRow(rowNumber, emptyRow);
    
    // 可選：使用 batchUpdate 真正刪除行（更複雜）
    // 這裡簡化處理，只清空內容
  }

  /// 批量更新操作（用於多個操作的優化）
  Future<void> batchUpdate(List<sheets.Request> requests) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized. Call initSheetsApi() first.');
    }

    final batchUpdateRequest = sheets.BatchUpdateSpreadsheetRequest(
      requests: requests,
    );

    await _sheetsApi!.spreadsheets.batchUpdate(
      batchUpdateRequest,
      spreadsheetId,
    );
  }

  /// 獲取表格的總行數
  Future<int> getTotalRows() async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized. Call initSheetsApi() first.');
    }

    final response = await _sheetsApi!.spreadsheets.values.get(
      spreadsheetId,
      '${range.split('!')[0]}!A:A', // 只讀取 A 列來計算行數
    );

    return response.values?.length ?? 0;
  }

  Future<void> deleteRow(int rowIndex) async {
    if (_sheetsApi == null) {
      throw Exception('Sheets API not initialized. Call initSheetsApi() first.');
    }
    final sheetName = range.split('!')[0];
    final deleteRequest = sheets.Request(
      deleteDimension: sheets.DeleteDimensionRequest(
        range: sheets.DimensionRange(
          sheetId: await _getSheetIdByName(sheetName),
          dimension: 'ROWS',
          startIndex: rowIndex - 1, // Google Sheets 是 0-based index
          endIndex: rowIndex,
        ),
      ),
    );
    final batchUpdateRequest = sheets.BatchUpdateSpreadsheetRequest(
      requests: [deleteRequest],
    );
    await _sheetsApi!.spreadsheets.batchUpdate(
      batchUpdateRequest,
      spreadsheetId,
    );
    await buildTimestampRowCache();
  }

  Future<int> _getSheetIdByName(String sheetName) async {
    final spreadsheet = await _sheetsApi!.spreadsheets.get(spreadsheetId);
    final sheet = spreadsheet.sheets!.firstWhere(
      (s) => s.properties!.title == sheetName,
      orElse: () => throw Exception('找不到表格 $sheetName'),
    );
    return sheet.properties!.sheetId!;
  }
}