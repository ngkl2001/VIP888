import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/daily_data_provider.dart';
import 'package:provider/provider.dart';
import '../services/daily_sync_service.dart';
import '../utils/time_utils.dart';

/// 通用記帳表單
class GeneralEntryForm extends StatefulWidget {
  final List<String> existingCategories;
  final Map<String, String>? initialData;
  final Function(Map<String, dynamic>) onSaved;
  final DateTime? now; // ✅ 新增這行


  const GeneralEntryForm({
    Key? key,
    required this.existingCategories,
    this.initialData,
    required this.onSaved,
    this.now, // ✅ 加這行
  }) : super(key: key);

  @override
  State<GeneralEntryForm> createState() => _GeneralEntryFormState();
}

class _GeneralEntryFormState extends State<GeneralEntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _categoryController = TextEditingController();
  final _detailsController = TextEditingController();
  final _aedController = TextEditingController();
  final _usdtController = TextEditingController();
  final _cnyController = TextEditingController();
  final _onlineController = TextEditingController();
  final _editNoteController = TextEditingController();

  String _selectedCategory = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _categoryController.text = widget.initialData!['category'] ?? '';
      _detailsController.text = widget.initialData!['details'] ?? '';
      _aedController.text = widget.initialData!['aed'] ?? '';
      _usdtController.text = widget.initialData!['usdt'] ?? '';
      _cnyController.text = widget.initialData!['cny'] ?? '';
      _onlineController.text = widget.initialData!['online'] ?? '';
    }
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _detailsController.dispose();
    _aedController.dispose();
    _usdtController.dispose();
    _cnyController.dispose();
    _onlineController.dispose();
    _editNoteController.dispose();
    super.dispose();
  }

  void _saveForm() {
    if (_formKey.currentState!.validate()) {
      final now = widget.now ?? Provider.of<DailySyncService>(context, listen: false).getDubaiTime();
      final data = {
        'timestamp': formatTimestampForSheet(now),
        'category': _categoryController.text.trim(),
        'details': _detailsController.text.trim(),
        'aed': _aedController.text.trim(),
        'usdt': _usdtController.text.trim(),
        'cny': _cnyController.text.trim(),
        'online': _onlineController.text.trim(),
        'edit_note': _editNoteController.text.trim(),
        'last_modified': formatTimestampForSheet(now),
      };

      widget.onSaved(data);
      Navigator.of(context).pop();
    }
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '新增記帳',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              
              // 類別選擇或輸入
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _categoryController,
                      decoration: const InputDecoration(
                        labelText: '類別',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '請輸入類別';
                        }
                        return null;
                      },
                    ),
                  ),
                  if (widget.existingCategories.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down),
                      onSelected: (value) {
                        setState(() {
                          _categoryController.text = value;
                        });
                      },
                      itemBuilder: (context) => widget.existingCategories
                          .map((cat) => PopupMenuItem(
                                value: cat,
                                child: Text(cat),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              
              // 明細
              TextFormField(
                controller: _detailsController,
                decoration: const InputDecoration(
                  labelText: '明細',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '請輸入明細';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              
              // 金額輸入
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _aedController,
                      decoration: const InputDecoration(
                        labelText: '迪拉姆 (AED)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _usdtController,
                      decoration: const InputDecoration(
                        labelText: 'USDT',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cnyController,
                      decoration: const InputDecoration(
                        labelText: '人民幣 (CNY)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _onlineController,
                      decoration: const InputDecoration(
                        labelText: '線上刷卡',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // 備註
              TextFormField(
                controller: _editNoteController,
                decoration: const InputDecoration(
                  labelText: '備註（選填）',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              
              // 按鈕
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saveForm,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
} 