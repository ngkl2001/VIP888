//本地 SQLite 相關邏輯

// lib/repositories/daily_data_repository.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:developer' as developer;

class DailyDataRepository {
  Database? _db;
  
  // Web平台使用內存存儲
  List<Map<String, dynamic>> _webData = [];
  int _webIdCounter = 1;

  // 取得資料庫實例
  Database? get db => _db;

  /// 初始化資料庫
  Future<void> initDatabase() async {
    if (kIsWeb) {
      // Web 平台：使用內存存儲
      print('運行在 Web 平台，使用內存存儲');
      _webData = [];
      _webIdCounter = 1;
      return;
    }
    
    // 原有的 SQLite 初始化代碼
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'daily_data_app.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // 建立 daily_data 表格 (針對你的九個欄位)
        await db.execute('''
          CREATE TABLE daily_data(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT UNIQUE,
            category TEXT,
            details TEXT,
            aed REAL,
            usdt REAL,
            cny REAL,
            online REAL DEFAULT 0.0,
            edit_note TEXT,
            last_modified TEXT
          )
        ''');
      },
    );
  }

  /// 新增一筆資料
  Future<int> insertData(Map<String, dynamic> data) async {
    try {
      if (kIsWeb) {
        final newData = Map<String, dynamic>.from(data);
        newData['id'] = _webIdCounter++;
        _webData.add(newData);
        return newData['id'];
      }
      if (_db == null) throw Exception('Database not initialized');
      return await _db!.insert('daily_data', data);
    } catch (e, stack) {
      developer.log('[DB] insertData error', error: e, stackTrace: stack);
      rethrow;
    }
  }


  Future<void> insertBatch(List<Map<String, dynamic>> dataList) async {
    try {
      if (kIsWeb) {
        for (final data in dataList) {
          final newData = Map<String, dynamic>.from(data);
          newData['id'] = _webIdCounter++;
          _webData.add(newData);
        }
        return;
      }
      if (_db == null) throw Exception('Database not initialized');
      await _db!.transaction((txn) async {
        for (final data in dataList) {
          await txn.insert(
            'daily_data',
            data,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (e, stack) {
      developer.log('[DB] insertBatch error', error: e, stackTrace: stack);
      rethrow;
    }
  }



  /// 取得所有 daily_data 的資料
  Future<List<Map<String, dynamic>>> getAllData() async {
    if (kIsWeb) {
      // Web平台：返回內存中的數據
      return List<Map<String, dynamic>>.from(_webData);
    }
    
    if (_db == null) throw Exception('Database not initialized');
    return await _db!.query('daily_data');
  }

  // 如果需要更新、刪除，請在此加上相應的函式...
  // daily_data_repository.dart
  Future<Map<String, dynamic>?> findByTimestamp(String timestamp) async {
    if (kIsWeb) {
      // Web平台處理
      try {
        return _webData.firstWhere(
          (item) => item['timestamp'] == timestamp,
        );
      } catch (e) {
        return null;
      }
    }
    
    if (_db == null) throw Exception('Database not initialized');
    final result = await _db!.query(
      'daily_data',
      where: 'timestamp = ?',
      whereArgs: [timestamp],
    );
    if (result.isEmpty) {
      return null; // 找不到
    }
    return result.first; // 找到就回傳第一筆
  }

  Future<int> updateData(Map<String, dynamic> data) async {
    try {
      if (kIsWeb) {
        final timestamp = data['timestamp'];
        final index = _webData.indexWhere(
          (item) => item['timestamp'] == timestamp,
        );
        if (index != -1) {
          _webData[index] = Map<String, dynamic>.from(data);
          return 1;
        }
        return 0;
      }
      if (_db == null) throw Exception('Database not initialized');
      return await _db!.update(
        'daily_data',
        data,
        where: 'timestamp = ?',
        whereArgs: [data['timestamp']],
      );
    } catch (e, stack) {
      developer.log('[DB] updateData error', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// 删除指定timestamp的数据
  Future<int> deleteByTimestamp(String timestamp) async {
    if (kIsWeb) {
      // Web平台處理
      final beforeLength = _webData.length;
      _webData.removeWhere((item) => item['timestamp'] == timestamp);
      return beforeLength - _webData.length;
    }
    
    if (_db == null) throw Exception('Database not initialized');
    return await _db!.delete(
      'daily_data',
      where: 'timestamp = ?',
      whereArgs: [timestamp],
    );
  }

  /// 清空所有数据 (用于完全重新同步)
  Future<int> clearAllData() async {
    if (kIsWeb) {
      // Web平台處理
      final count = _webData.length;
      _webData.clear();
      _webIdCounter = 1;
      return count;
    }
    
    if (_db == null) throw Exception('Database not initialized');
    return await _db!.delete('daily_data');
  }

  /// 获取所有timestamp列表 (用于对比)
  Future<List<String>> getAllTimestamps() async {
    if (kIsWeb) {
      // Web平台處理
      return _webData
          .map((item) => item['timestamp'].toString())
          .toList();
    }
    
    if (_db == null) throw Exception('Database not initialized');
    final result = await _db!.query(
      'daily_data',
      columns: ['timestamp'],
    );
    return result.map((row) => row['timestamp'].toString()).toList();
  }

  /// 获取数据记录数量
  Future<int> getDataCount() async {
    if (kIsWeb) {
      // Web平台處理
      return _webData.length;
    }
    
    if (_db == null) throw Exception('Database not initialized');
    final result = await _db!.rawQuery('SELECT COUNT(*) as count FROM daily_data');
    return result.first['count'] as int;
  }

}