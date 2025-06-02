// 同步配置參數

class SyncConfig {
  /// 最大重試次數
  static const int maxRetries = 3;
  
  /// 重試延遲時間（秒）
  static const int baseRetryDelaySeconds = 2;
  
  /// 是否在應用啟動時自動同步
  static const bool autoSyncOnStartup = true;
  
  /// 同步超時時間（秒）
  static const int syncTimeoutSeconds = 30;
  
  /// 是否保留本地獨有數據（true=上傳到雲端，false=刪除本地）
  static const bool preserveLocalOnlyData = true;
  
  /// 是否在雲端刪除數據時同步刪除本地數據
  static const bool syncDeletes = false;
  
  /// 數據衝突時的處理策略
  /// - 'cloud_wins': 雲端優先
  /// - 'local_wins': 本地優先  
  /// - 'latest_wins': 最新修改時間優先
  static const String conflictResolution = 'cloud_wins';
  
  /// 是否顯示詳細的同步日誌
  static const bool verboseLogging = true;
  
  /// 計算重試延遲時間
  static Duration getRetryDelay(int retryCount) {
    return Duration(seconds: baseRetryDelaySeconds * retryCount);
  }
}
