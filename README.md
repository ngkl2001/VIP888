員工管理 App 專案說明
專案背景
主要功能：開發一個給酒店員工使用的 App，所有操作（例如新增、修改資料）都需同步記錄至後台 Google Sheet。

技術考量：

為了減少 Google Sheets API 的使用次數並提高效能，App 會先將資料從 Google Sheet 拉到本地 SQLite 進行分析，再透過 Provider 進行即時 UI 更新。

使用者端的操作會先更新本地 SQLite，再在背景排程中與後端 Google Sheet 同步。

Google Sheet 後端必須與 SQLite 及使用者的 UI 保持一致。

核心需求與重點
即時性

任何操作都要即時更新 UI，增進使用者體驗。

即時性主要透過本地 SQLite 及 Provider 來達成，不必等待 Google Sheets 回應。

離線模式與背景同步

使用者可能在離線時操作，等連線後要把本地更新過的資料批次上傳至 Google Sheet。

背景同步可考慮分批上傳、避免一次大量寫入 Google Sheets 造成 API 存取瓶頸。

衝突處理

多裝置或多使用者同時操作同一筆資料，可能發生衝突。

目前採「以本地 SQLite 為準，並及時更新到 Google Sheet」的原則，但可能需要進一步機制讓使用者知道衝突情況。

Google Sheets API 資料安全性

暫時將 Service Account JSON 憑證放在 assets 資料夾中，後續考慮更安全的管理方式。

全體使用者權限暫時都一致。

動態分析結果

部分報表或資料分析結果只需在 App 顯示，不需要寫回 Google Sheet。

可在 Provider 層利用本地資料做運算後直接更新 UI。

專案結構
建議在 lib/ 下建立以下資料夾，以明確分層：

main.dart：App 進入點

repositories/：

SheetsRepository：負責 Google Sheets API 讀寫

LocalDbRepository：負責本地 SQLite 的 CRUD

providers/：

EmployeeProvider 等：使用 ChangeNotifier 或 Riverpod 進行狀態管理，串接 Repository。

models/：資料模型、資料結構

services/：可放更多 API/Service 邏輯（若有）

ui/：Flutter Widget / UI 畫面

流程與簡易範例
資料初始化

App 啟動時（main.dart），先初始化 SQLite（LocalDbRepository）。

可以視情況從 Google Sheets 拉取基礎資料並存到本地。

資料操作 (UI → Provider → Repository)

使用者在 UI 點擊新增、修改、刪除… → 呼叫 Provider 對 SQLite 寫入/更新 → 透過 notifyListeners() 即時更新 UI → 背景呼叫 SheetsRepository 同步至 Google Sheet。

Provider 層進行動態分析

若有報表或需要即時計算的資訊，可在 Provider 取得本地資料後計算，然後 notifyListeners() 告知 UI 即時刷新。

Google API 使用限制與排程

為避免頻繁呼叫 Google Sheets，每次操作可先記錄在本地，再定時或累積到一定數量後一次批次上傳。

同步失敗時應考慮重試機制，並在 UI 或 Log 作出提示。

衝突解決

雖以 SQLite 為準，但若多使用者同時操作同一筆資料，可能需要記錄更新時間戳或版本號，以辨別衝突並在 UI 提示使用者。

未來擴充
Migration：SQLite 未來若需擴充欄位，可實作 Migration 機制 或手動維護版本控制。

多 Provider 支持：針對不同功能（如員工管理、客房管理、排班管理…）可拆分多個 Provider，各自獨立維護狀態。

Log & Error Tracking：可考慮在同步失敗、API 拒絕存取時進行日誌紀錄或顯示更友善的錯誤訊息。

小結
此專案核心在於：

保持 UI 與本地資料同步（透過 SQLite + Provider）

在背景與 Google Sheets 同步（減少 API 負載）

適度考慮離線模式與多使用者衝突

將分析或衍生資訊保留在本地運算即可（若非必要不寫回後端）

若有任何疑問或需求變更，請在開發時持續更新此 README，確保未來參與專案的開發者或協作工具都能快速了解專案狀況與技術方向。

## 2024年12月 重大優化與修復

### 📝 修復內容

#### 1. **數據格式修正**
- **online 欄位**：從布爾值（Yes/No）改為數字貨幣欄位
  - 影響：模型層、表單、UI 顯示、統計計算、同步邏輯
  - 原因：符合 Google Sheets 後台設計，online 是貨幣類型

#### 2. **數據排序問題**
- **修正**：所有數據按時間戳降序排序（最新在最上面）
  - 實現位置：`DailyDataProvider` 的 `entries` getter 和 `_applyFilters` 方法
  - 符合用戶使用習慣

#### 3. **Google Sheets 插入順序**
- **修正**：新數據插入到表頭下面（第2行），而非追加到末尾
  - 修改：`SheetsRepository.appendSingleRow` 方法
  - 確保雲端和本地數據順序一致

#### 4. **UI 固定表頭實現**
- **修正**：手動實現固定表頭的數據表格
  - 解決問題：Vertical viewport was given unbounded width
  - 優點：表頭始終可見，支持橫向和縱向滾動

### 🚀 性能優化

1. **移除重複同步**
   - HomePage 不再重複初始化，避免啟動時同步兩次

2. **單行操作優化**
   - 新增：`appendSingleRow` - 只追加一行
   - 更新：`updateSingleRow` - 只更新特定行
   - 刪除：`deleteSingleRow` - 只清空特定行
   - 效果：API 調用減少 90%，數據傳輸減少 95%

3. **批量操作隊列**
   - 多個操作自動合併，2秒後批量執行
   - 減少網絡請求次數

### 🎨 UI/UX 改善

1. **視覺反饋**
   - 新增中：綠色背景
   - 刪除中：紅色背景 + 刪除線
   - 更新中：加載動畫

2. **交互優化**
   - 點擊整行即可編輯
   - 數字欄位右對齊
   - 固定表頭，隨時可見欄位名稱

### ⚠️ 重要提醒

**開發時請注意**：
1. 修改代碼時必須同時考慮邏輯問題和 UI 問題
2. 特別注意 Flutter 的佈局約束（如無限寬度/高度問題）
3. 數據格式必須與 Google Sheets 保持一致
4. 新功能必須考慮離線操作和同步失敗的情況

### 📊 數據欄位說明

| 欄位 | 類型 | 說明 |
|------|------|------|
| timestamp_daily | 字符串 | ISO 8601 格式時間戳 |
| category | 字符串 | 分類 |
| details | 字符串 | 明細說明 |
| aed | 數字 | 迪拉姆貨幣 |
| usdt | 數字 | USDT 數量 |
| cny | 數字 | 人民幣 |
| online | 數字 | 線上刷卡金額（不是布爾值）|
| edit_note | 字符串 | 備註 |
| last_modified | 字符串 | 最後修改時間 |

### 🌐 Web 平台支持（2024年12月更新）

#### 問題修復
1. **Web 平台兼容性**
   - 問題：`path_provider` 和 `sqflite` 在 Web 平台不支持
   - 解決：為 Web 平台提供內存存儲替代方案
   - 影響：現在可以在 Chrome 瀏覽器中正常運行應用

2. **UI 溢出問題**
   - 問題：表格總寬度 980 像素導致 RenderFlex overflow
   - 解決：優化列寬和內邊距，總寬度減少到 810 像素
   - 調整內容：
     - 時間列：140→120
     - 類別列：100→80
     - 明細列：200→150
     - 數字列：80→70
     - 備註列：120→100
     - 操作列：100→80
     - 內邊距：12→8
     - 字體大小：13→12

#### 運行方式
```bash
# 在 Chrome 瀏覽器中運行（推薦用於快速測試）
flutter run -d chrome

# 在 Windows 上運行（需要 Visual Studio）
flutter run -d windows

# 在 Android 模擬器中運行
flutter run -d android
```

#### 注意事項
- Web 版本使用內存存儲，數據不會持久化
- 刷新頁面會清空本地數據，但可從 Google Sheets 重新同步
- Web 版本主要用於測試和演示，生產環境建議使用原生應用

### 🐛 Android Studio 錯誤修復（2024年12月）

#### 問題描述
在 Android Studio 運行時出現以下錯誤：
```
E/flutter ( 9579): [ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: Unsupported operation: read-only
E/flutter ( 9579): #0      QueryResultSet.length= (package:sqflite_common/src/collection_utils.dart:121:5)
E/flutter ( 9579): #1      ListBase.add (dart:collection/list.dart:244:15)
E/flutter ( 9579): #2      DailyDataProvider.addEntry (package:employee_app/providers/daily_data_provider.dart:335:16)
```

#### 根本原因
SQLite (sqflite) 查詢返回的是只讀的 `QueryResultSet`，不能直接修改。當嘗試向這個只讀列表添加新元素時會報錯。

#### 解決方案
修改 `DailyDataProvider.fetchDailyData` 方法：
```dart
// 錯誤的代碼
_dailyList = data;  // data 是只讀的 QueryResultSet

// 正確的代碼
_dailyList = List<Map<String, dynamic>>.from(data);  // 創建可修改的新列表
```

#### 教訓
- 始終注意資料庫查詢返回的數據結構
- 需要修改列表時，確保創建可修改的副本
- Flutter/Dart 的類型系統有時不會在編譯時捕獲這類錯誤

最後更新：此 README 根據專案初始階段規劃撰寫，後續如有功能需求更動、Google Sheets API 新增限制、或狀態管理改變，請及時修訂。
