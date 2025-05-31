//App 進入點與 Provider 注入

// 匯入 Flutter 核心元件與 Material Design 小工具 (Widget)。
// MaterialApp、Scaffold、Text 等元件都在這個套件中。
import 'package:flutter/material.dart';

// 匯入 Provider 套件，主要用來做狀態管理。
// 透過 Provider 可以在整個應用中共享某些物件 (像 Repository 或 ChangeNotifier)。
import 'package:provider/provider.dart';

// 自己專案裡的檔案：repositories/daily_data_repository.dart
// 這個檔案裡面通常定義與資料庫或 API 有關的「存取層」(Repository)。
import 'dart:developer' as developer;

// 自己專案裡的檔案：repositories/daily_data_repository.dart
import 'repositories/daily_data_repository.dart';

// 自己專案裡的檔案：providers/daily_data_provider.dart
// 這個檔案定義了 DailyDataProvider，繼承 ChangeNotifier，負責管理資料與通知 UI。
import 'providers/daily_data_provider.dart';

// 自己專案裡的檔案：ui/home_page.dart
// 這個檔案定義了主畫面 HomePage，顯示資料列表或提供操作入口。
import 'ui/home_page.dart';

import 'repositories/sheets_repository.dart';
import 'config/sync_config.dart';



// main() 函式是 Flutter 專案的入口點。
// 所有 Flutter App 都是從這裡開始執行。
Future<void> main() async {
  // 確保 Widgets 系統（繪圖、綁定等）已經正確初始化。
  // 如果需要與原生平台溝通 (像使用 sqflite)，常常要先呼叫這一行。
  WidgetsFlutterBinding.ensureInitialized();

  // 建立一個 DailyDataRepository 實例，用來管理本地資料庫 (SQLite)。
  final dailyRepo = DailyDataRepository();

  // 初始化資料庫，可能包含建立資料表、連線等動作。
  await dailyRepo.initDatabase();

  // 2. 初始化 Google Sheets
  final sheetsRepo = SheetsRepository(
    spreadsheetId: '1KtgcDwkrKCDLJHOAwgmG32JHzj3A23fW2HxG4zcUnnQ',
    serviceAccountJsonPath: 'assets/imposing-ring-453707-q0-b4925b0385fe.json',
    range: 'daily!A1:I',
  );
  await sheetsRepo.initSheetsApi();

  // 建立一個 DailyDataProvider 實例，並把上面建好的 Repository 傳進去。
  // DailyDataProvider 負責跟資料庫互動並存放資料給 UI 使用。
  // 3. 建立 Provider (DailyDataProvider) 時注入 sheetsRepo
  final dailyProvider = DailyDataProvider(
    dailyRepo: dailyRepo,
    sheetsRepo: sheetsRepo,
  );

  // ★★★ 在這裡「自動」從雲端進行完整雙向同步
  developer.log('開始執行應用啟動時的雙向同步...', name: 'main');
  
  bool syncSuccess = false;
  int retryCount = 0;
  
  if (SyncConfig.autoSyncOnStartup) {
    while (!syncSuccess && retryCount < SyncConfig.maxRetries) {
      try {
        retryCount++;
        developer.log('嘗試同步 (第 $retryCount 次)...', name: 'main');
        
        // 使用新的完整雙向同步方法
        syncSuccess = await dailyProvider.fullBidirectionalSync();
        
        if (syncSuccess) {
          developer.log('應用啟動同步成功完成！', name: 'main');
        } else {
          developer.log('同步失败，將重試...', name: 'main');
          // 等待一段時間後重試
          if (retryCount < SyncConfig.maxRetries) {
            await Future.delayed(SyncConfig.getRetryDelay(retryCount));
          }
        }
      } catch (e) {
        developer.log('啟動同步發生錯誤 (第 $retryCount 次): $e', name: 'main');
        if (retryCount < SyncConfig.maxRetries) {
          await Future.delayed(SyncConfig.getRetryDelay(retryCount));
        }
      }
    }
    
    if (!syncSuccess) {
      developer.log('啟動同步最終失敗，應用將以本地數據運行', name: 'main');
    }
  } else {
    developer.log('自動同步已禁用，應用以本地數據啟動', name: 'main');
  }


  // 這裡使用 MultiProvider 可以一次提供多個物件給全應用使用。
  // providers 陣列裡可以放 Provider 或 ChangeNotifierProvider 來共享實例。
  runApp(
    MultiProvider(
      providers: [
        // 把 dailyRepo 以 Provider<DailyDataRepository> 的形式提供給全應用。
        // 任何 Widget 只要透過 Provider.of<DailyDataRepository>(context) 就能拿到這個實例。
        Provider<DailyDataRepository>.value(value: dailyRepo),
        Provider<SheetsRepository>.value(value: sheetsRepo),

        // 把 dailyProvider (繼承自 ChangeNotifier) 提供給全應用。
        // 讓畫面可以透過 context.watch<DailyDataProvider>() 或
        // Provider.of<DailyDataProvider>(context) 取得或監聽裡面的資料。
        ChangeNotifierProvider<DailyDataProvider>.value(value: dailyProvider),
      ],
      // child 代表在這些 Provider 被註冊後，要執行哪個 Widget。
      // 這裡是執行整個應用的根 Widget MyApp。
      child: const MyApp(),
    ),
  );
}

// 這是整個應用的根 Widget，繼承自 StatelessWidget。
// 代表不需要內部狀態 (State) 的變動。
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // build(BuildContext context) 是 Flutter 中最核心的函式之一，
  // 負責回傳要顯示的畫面 (Widget)。
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // App 的標題。某些情況下會顯示在任務管理 (ex. Android 最近使用的 App)。
      title: 'Daily Data App',

      // 設定整個應用的主題色系。
      theme: ThemeData(primarySwatch: Colors.blue),

      // home 代表應用啟動後預設會顯示哪個 Widget。
      // 這裡使用我們在 ui/home_page.dart 定義的 HomePage 。
      home: const HomePage(),
    );
  }
}
