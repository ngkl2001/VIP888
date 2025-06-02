// lib/ui/home_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/daily_data_provider.dart';
import '../models/ledger_entry.dart';
import '../widgets/general_entry_form.dart';
import '../widgets/stat_item.dart';
import '../services/daily_sync_service.dart'; // ✅ 新增
import '../utils/format_utils.dart';
import '../utils/time_utils.dart';


class HomePage extends StatefulWidget {
  final Map<String, String>? initialLedgerData;
  
  const HomePage({Key? key, this.initialLedgerData}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 搜索控制器
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  
  // 缩放相关
  double _scaleFactor = 1.0;

  @override
  void initState() {
    super.initState();
    // 初始化 Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<DailyDataProvider>();
      // ⚡ 優化：移除重複的初始化
      // provider.initialize(); // 這會觸發重複同步
      
      // 只加載本地數據到內存，不觸發同步
      // 因為 main.dart 已經完成了初始同步
      provider.fetchDailyData();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // 搜索變化處理
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final provider = context.read<DailyDataProvider>();
      provider.setSearchQuery(value);
    });
  }

  // 選擇日期範圍
  Future<void> _pickDateRange() async {
    final provider = context.read<DailyDataProvider>();
    
    final pickedRange = await showDateRangePicker(
      context: context,
      initialDateRange: provider.startDate != null && provider.endDate != null
          ? DateTimeRange(start: provider.startDate!, end: provider.endDate!)
          : null,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    
    if (pickedRange != null) {
      provider.setDateRange(pickedRange.start, pickedRange.end);
    }
  }

  // 刪除記錄
  Future<void> _deleteEntry(LedgerEntry entry) async {
    // 顯示確認對話框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('確定要刪除這條記錄嗎？'),
            SizedBox(height: 8),
            Text(
              '注意：記錄將從本地和Google Sheets中永久刪除。',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final provider = context.read<DailyDataProvider>();
    
    try {
      await provider.deleteEntryLocalAndCloud(entry);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('刪除成功')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刪除失敗: $e')),
        );
      }
    }
  }

  // 顯示編輯對話框
  void _showEditSheet(LedgerEntry entry) {
    final categoryController = TextEditingController(text: entry.category);
    final detailsController = TextEditingController(text: entry.details);
    final aedController = TextEditingController(text: entry.aed.toString());
    final usdtController = TextEditingController(text: entry.usdt.toString());
    final cnyController = TextEditingController(text: entry.cny.toString());
    final onlineController = TextEditingController(text: entry.online.toString());
    final editNoteController = TextEditingController(text: entry.editNote);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '編輯 [32m[1m[4m${entry.formattedTimestamp}[0m',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(
                    labelText: '類別',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: detailsController,
                  decoration: const InputDecoration(
                    labelText: '明細',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: aedController,
                        decoration: const InputDecoration(
                          labelText: '迪',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: usdtController,
                        decoration: const InputDecoration(
                          labelText: 'U',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cnyController,
                        decoration: const InputDecoration(
                          labelText: '人',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: onlineController,
                        decoration: const InputDecoration(
                          labelText: '刷',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: editNoteController,
                  decoration: const InputDecoration(
                    labelText: '修改備註（可選）',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final newEntry = entry.copyWith(
                          category: categoryController.text.trim(),
                          details: detailsController.text.trim(),
                          aed: double.tryParse(aedController.text.trim()) ?? 0.0,
                          usdt: double.tryParse(usdtController.text.trim()) ?? 0.0,
                          cny: double.tryParse(cnyController.text.trim()) ?? 0.0,
                          online: double.tryParse(onlineController.text.trim()) ?? 0.0,
                          editNote: editNoteController.text.trim(),
                          lastModified: DateTime.now(),
                        );
                        
                        final provider = context.read<DailyDataProvider>();
                        try {
                          await provider.updateEntryLocalAndCloud(entry, newEntry);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('更新成功')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('更新失敗: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 顯示新增表單
  void _showEntryForm() {
    showDialog(
      context: context,
      builder: (context) {
        final now = Provider.of<DailySyncService>(context, listen: false).getDubaiTime();
        final provider = context.read<DailyDataProvider>();
        return Dialog(
          child: GeneralEntryForm(
            existingCategories: provider.existingCategories,
            initialData: widget.initialLedgerData,
            now: now,
            onSaved: (data) async {
              try {
                await provider.addEntryLocalAndCloud(LedgerEntry.fromMap(data));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('新增成功')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增失敗: $e')));
                }
              }
            },
          ),
        );
      },
    );
  }

  // 構建同步狀態指示器
  Widget _buildSyncStatusWidget(DailyDataProvider provider) {
    if (provider.syncStatus == SyncStatus.idle) {
      return const SizedBox.shrink();
    }

    Color bgColor;
    Color textColor;
    IconData icon;
    
    switch (provider.syncStatus) {
      case SyncStatus.syncing:
        bgColor = Colors.blue[100]!;
        textColor = Colors.blue;
        icon = Icons.sync;
        break;
      case SyncStatus.success:
        bgColor = Colors.green[100]!;
        textColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case SyncStatus.error:
        bgColor = Colors.red[100]!;
        textColor = Colors.red;
        icon = Icons.error;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: bgColor,
      child: Row(
        children: [
          if (provider.syncStatus == SyncStatus.syncing)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(textColor),
              ),
            )
          else
            Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.syncMessage,
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          ),
          if (provider.syncStatus != SyncStatus.syncing)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => provider.clearSyncStatus(),
            ),
        ],
      ),
    );
  }

  // 構建數據表格
  Widget _buildDataTable(List<LedgerEntry> entries, DailyDataProvider provider) {
    // 定義列寬 - 調整使其更緊湊
    const double timeWidth = 120;      // 從140減少到120
    const double categoryWidth = 80;   // 從100減少到80
    const double detailsWidth = 150;   // 從200減少到150
    const double numberWidth = 70;     // 從80減少到70
    const double noteWidth = 100;      // 從120減少到100
    const double actionWidth = 120;     // 從80增加到100
    
    final totalWidth = timeWidth + categoryWidth + detailsWidth + 
                      (numberWidth * 4) + noteWidth + actionWidth;
    
    // 構建表頭
    Widget buildHeader() {
      return Container(
        width: totalWidth,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border(
            bottom: BorderSide(color: Colors.grey[300]!, width: 2),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: timeWidth,
              child: Padding(
                padding: const EdgeInsets.all(8),  // 從12減少到8
                child: Text('時間', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),  // 添加fontSize
              ),
            ),
            SizedBox(
              width: categoryWidth,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('類別', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
            SizedBox(
              width: detailsWidth,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('明細', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
            SizedBox(
              width: numberWidth,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('迪', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
              ),
            ),
            SizedBox(
              width: numberWidth,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('U', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
              ),
            ),
            SizedBox(
              width: numberWidth,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('人', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
              ),
            ),
            SizedBox(
              width: numberWidth,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('刷', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
              ),
            ),
            SizedBox(
              width: noteWidth,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('備註', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
            SizedBox(
              width: actionWidth,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('操作', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      );
    }
    
    // 構建數據行
    Widget buildDataRow(LedgerEntry entry) {
      final isDeleting = provider.isOptimisticallyDeleted(entry.formatted);
      final isAdding = provider.isOptimisticallyAdded(entry.formatted);
      final isPending = provider.isPending(entry.formatted);
      
      final textStyle = TextStyle(
        fontSize: 12,  // 從13減少到12
        color: isDeleting ? Colors.red : isAdding ? Colors.green : null,
        decoration: isDeleting ? TextDecoration.lineThrough : null,
        fontStyle: (isDeleting || isAdding || isPending) ? FontStyle.italic : null,
      );
      
      final bgColor = isDeleting ? Colors.red[50] : 
                     isAdding ? Colors.green[50] : 
                     null;
      
      return Container(
        width: totalWidth,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showEditSheet(entry),
            child: Row(
              children: [
                SizedBox(
                  width: timeWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(entry.formattedTimestamp, style: textStyle),
                  ),
                ),
                SizedBox(
                  width: categoryWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(entry.category, style: textStyle, overflow: TextOverflow.ellipsis),
                  ),
                ),
                SizedBox(
                  width: detailsWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(entry.details, style: textStyle, overflow: TextOverflow.ellipsis, maxLines: 2),
                  ),
                ),
                SizedBox(
                  width: numberWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(formatMoney(entry.aed), style: textStyle, textAlign: TextAlign.right),
                  ),
                ),
                SizedBox(
                  width: numberWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(formatMoney(entry.usdt), style: textStyle, textAlign: TextAlign.right),
                  ),
                ),
                SizedBox(
                  width: numberWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(formatMoney(entry.cny), style: textStyle, textAlign: TextAlign.right),
                  ),
                ),
                SizedBox(
                  width: numberWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(formatMoney(entry.online), style: textStyle, textAlign: TextAlign.right),
                  ),
                ),
                SizedBox(
                  width: noteWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(entry.editNote, style: textStyle, overflow: TextOverflow.ellipsis),
                  ),
                ),
                SizedBox(
                  width: actionWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),  // 調整padding
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 16),
                          onPressed: (isDeleting || isPending) ? null : () => _showEditSheet(entry),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(minWidth: 24, minHeight: 24),  // 從28減少到24
                        ),
                        if (isPending || isDeleting)
                          const SizedBox(
                            width: 16,  // 從18減少到16
                            height: 16,  // 從18減少到16
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.delete, size: 16),
                            onPressed: () => _deleteEntry(entry),
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(minWidth: 24, minHeight: 24),  // 從28減少到24
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // 主體結構：固定表頭 + 可滾動內容
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // 固定表頭
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: buildHeader(),
            ),
            // 可滾動的內容區域
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: totalWidth,
                  child: ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) => buildDataRow(entries[index]),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DailyDataProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Text('每日帳本'),
                // 操作狀態指示器
                if (provider.hasPendingDeletes)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, size: 10, color: Colors.white),
                          SizedBox(width: 2),
                          Text('刪除中', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                if (provider.hasPendingAdds)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle_outline, size: 10, color: Colors.white),
                          SizedBox(width: 2),
                          Text('新增中', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 20),
                // 搜索框
                Expanded(
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索分類、明細...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      ),
                      style: const TextStyle(fontSize: 14),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              // 日期篩選
              IconButton(
                icon: const Icon(Icons.date_range),
                onPressed: _pickDateRange,
                tooltip: '選擇日期',
              ),
              // 刷新
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: provider.isLoading
                    ? null
                    : () async {
                  final result = await provider.refresh();
                  if (!result && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('刷新失敗，請稍後再試')),
                    );
                  }
                },
                tooltip: '重新載入',
              ),

              // 強制同步
              if (provider.hasPendingOperations)
                IconButton(
                  icon: const Icon(Icons.cloud_upload),
                  onPressed: () => provider.fullBidirectionalSync(),
                  tooltip: '強制同步',
                ),
              // 縮放控制
              IconButton(
                icon: const Icon(Icons.zoom_in),
                onPressed: () => setState(() => _scaleFactor *= 1.2),
                tooltip: '放大',
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out),
                onPressed: () => setState(() => _scaleFactor *= 0.8),
                tooltip: '縮小',
              ),
              IconButton(
                icon: const Icon(Icons.settings_backup_restore),
                onPressed: () => setState(() => _scaleFactor = 1.0),
                tooltip: '重置大小',
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // 同步狀態
                _buildSyncStatusWidget(provider),
                
                // 統計面板
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              StatItem(label: '迪', value: provider.totalAED, color: Colors.black),
                              const SizedBox(width: 24),
                              StatItem(label: 'U', value: provider.totalUSDT, color: Colors.black),
                              const SizedBox(width: 24),
                              StatItem(label: '人', value: provider.totalCNY, color: Colors.black),
                              const SizedBox(width: 24),
                              StatItem(label: '刷', value: provider.totalOnline, color: Colors.black),
                              const SizedBox(width: 24),
                              StatItem(label: '筆數', value: provider.filteredEntries.length.toDouble(), color: Colors.black),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 日期篩選提示
                if (provider.startDate != null || provider.endDate != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.amber[100],
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '篩選日期：[32m[1m[4m${provider.startDate != null ? provider.startDate!.formattedTimestamp : '不限'}[0m 至 [32m[1m[4m${provider.endDate != null ? provider.endDate!.formattedTimestamp : '不限'}[0m',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () => provider.clearDateFilter(),
                          child: const Text('清除'),
                        ),
                      ],
                    ),
                  ),
                
                // 數據表格
                Expanded(
                  child: Transform.scale(
                    scale: _scaleFactor,
                    alignment: Alignment.topLeft,
                    child: provider.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : provider.error.isNotEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                                    const SizedBox(height: 16),
                                    Text(
                                      provider.error,
                                      style: const TextStyle(fontSize: 16, color: Colors.red),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: () => provider.refresh(),
                                      child: const Text('重試'),
                                    ),
                                  ],
                                ),
                              )
                            : provider.filteredEntries.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.receipt_long, size: 48, color: Colors.grey),
                                        const SizedBox(height: 16),
                                        Text(
                                          provider.searchQuery.isNotEmpty 
                                              ? '沒有找到符合條件的記錄' 
                                              : '尚無記帳資料',
                                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                                        ),
                                        if (provider.searchQuery.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          TextButton(
                                            onPressed: () {
                                              _searchController.clear();
                                              provider.setSearchQuery('');
                                            },
                                            child: const Text('清除搜索'),
                                          ),
                                        ],
                                      ],
                                    ),
                                  )
                                : RefreshIndicator(
                                    onRefresh: () => provider.fullBidirectionalSync(),
                                    child: _buildDataTable(provider.filteredEntries, provider),
                                  ),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _showEntryForm,
            tooltip: '新增',
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}
