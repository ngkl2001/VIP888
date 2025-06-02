import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:developer' as developer;
import 'repositories/daily_data_repository.dart';
import 'repositories/sheets_repository.dart';
import 'providers/daily_data_provider.dart';
import 'services/daily_sync_service.dart';
import 'ui/home_page.dart';
import 'config/sync_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化本地資料庫與 Google Sheets API
  final dailyRepo = DailyDataRepository();
  await dailyRepo.initDatabase();

  final sheetsRepo = SheetsRepository(
    spreadsheetId: '1KtgcDwkrKCDLJHOAwgmG32JHzj3A23fW2HxG4zcUnnQ',
    serviceAccountJsonPath: 'assets/imposing-ring-453707-q0-b4925b0385fe.json',
    range: 'daily!A1:I',
  );
  await sheetsRepo.initSheetsApi();

  final syncService = DailySyncService(
    dailyRepo: dailyRepo,
    sheetsRepo: sheetsRepo,
  );

  final dailyProvider = DailyDataProvider(
    dailyRepo: dailyRepo,
    sheetsRepo: sheetsRepo,
  );

  // ✅ Step 1: 上傳所有尚未處理的排程操作（不要清空 SQLite）
  developer.log('🚀 執行啟動上傳排程資料...', name: 'main');
  await syncService.executeBatchSync(dailyProvider.operationQueue);
  dailyProvider.clearOperationQueue();

  // ✅ Step 2: 啟動 UI，資料來自本地 SQLite（即時可用）
  runApp(
    MultiProvider(
      providers: [
        Provider<DailyDataRepository>.value(value: dailyRepo),
        Provider<SheetsRepository>.value(value: sheetsRepo),
        Provider<DailySyncService>.value(value: syncService),
        ChangeNotifierProvider<DailyDataProvider>.value(value: dailyProvider),
      ],
      child: const MyApp(),
    ),
  );

  // ✅ Step 3: 背景全量同步雲端資料 → 覆蓋本地 SQLite
  Future.microtask(() async {
    developer.log('🔄 背景啟動：全量下載並覆蓋 SQLite...', name: 'main');
    final success = await syncService.fullBidirectionalSync();
    if (success) {
      await dailyProvider.fetchDailyData();
    }
  });
}

// UI 主入口
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Data App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}
