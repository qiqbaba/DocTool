import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/delete_logic.dart';
import '../utils/theme_helper.dart';

class DeleteRulePanel extends StatefulWidget {
  final DeleteFilterRule initialRule;
  final bool initialRecursive;
  final Function(DeleteFilterRule rule, bool recursive) onChanged;

  const DeleteRulePanel({
    super.key,
    required this.initialRule,
    required this.initialRecursive,
    required this.onChanged,
  });

  @override
  State<DeleteRulePanel> createState() => _DeleteRulePanelState();
}

class _DeleteRulePanelState extends State<DeleteRulePanel> {
  late DeleteFilterRule _rule;
  late bool _recursive;

  // Controllers
  final TextEditingController _extController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _sizeValueController = TextEditingController();
  final TextEditingController _hashController = TextEditingController();
  final TextEditingController _timeDaysController = TextEditingController();

  SizeUnit _selectedSizeUnit = SizeUnit.kb;
  bool _isCalculatingMd5 = false;

  @override
  void initState() {
    super.initState();
    _rule = widget.initialRule;
    _recursive = widget.initialRecursive;

    // Initialize controller texts
    _extController.text = _rule.extensionFilter;
    _nameController.text = _rule.nameContains;
    
    // Deconstruct size value back to unit for UI
    if (_rule.sizeValueBytes == 0) {
      _sizeValueController.text = '';
      _selectedSizeUnit = SizeUnit.kb;
    } else {
      final bytes = _rule.sizeValueBytes;
      if (bytes >= 1024 * 1024 * 1024 && bytes % (1024 * 1024 * 1024) == 0) {
        _sizeValueController.text = (bytes / (1024 * 1024 * 1024)).toStringAsFixed(0);
        _selectedSizeUnit = SizeUnit.gb;
      } else if (bytes >= 1024 * 1024 && bytes % (1024 * 1024) == 0) {
        _sizeValueController.text = (bytes / (1024 * 1024)).toStringAsFixed(0);
        _selectedSizeUnit = SizeUnit.mb;
      } else if (bytes >= 1024 && bytes % 1024 == 0) {
        _sizeValueController.text = (bytes / 1024).toStringAsFixed(0);
        _selectedSizeUnit = SizeUnit.kb;
      } else {
        _sizeValueController.text = bytes.toString();
        _selectedSizeUnit = SizeUnit.b;
      }
    }

    _hashController.text = _rule.targetHash;
    _timeDaysController.text = _rule.timeDays.toString();

    // Listeners for triggers
    _extController.addListener(() {
      _rule = _rule.copyWith(extensionFilter: _extController.text);
      _triggerChanged();
    });
    _nameController.addListener(() {
      _rule = _rule.copyWith(nameContains: _nameController.text);
      _triggerChanged();
    });
    _sizeValueController.addListener(() {
      _updateSizeBytes();
    });
    _hashController.addListener(() {
      final text = _hashController.text.trim();
      if (text != _rule.targetHash) {
        _rule = _rule.copyWith(
          targetHash: text,
          targetHashSize: null, // Clear size filter upon manual keyboard typing
        );
        _triggerChanged();
      }
    });
    _timeDaysController.addListener(() {
      final days = int.tryParse(_timeDaysController.text) ?? 30;
      _rule = _rule.copyWith(timeDays: days);
      _triggerChanged();
    });
  }

  @override
  void dispose() {
    _extController.dispose();
    _nameController.dispose();
    _sizeValueController.dispose();
    _hashController.dispose();
    _timeDaysController.dispose();
    super.dispose();
  }

  Future<void> _pickFileAndCalculateMd5() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _isCalculatingMd5 = true;
        });

        final file = File(result.files.single.path!);
        final md5Hash = await DeleteLogic.calculateFileMd5(file);
        final size = await file.length();

        setState(() {
          _rule = _rule.copyWith(
            targetHash: md5Hash,
            targetHashSize: size,
          );
          _hashController.text = md5Hash;
          _isCalculatingMd5 = false;
        });
        _triggerChanged();
      }
    } catch (e) {
      setState(() {
        _isCalculatingMd5 = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('计算文件MD5失败: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _triggerChanged() {
    widget.onChanged(_rule, _recursive);
  }

  void _updateSizeBytes() {
    final val = double.tryParse(_sizeValueController.text) ?? 0.0;
    int bytes = 0;
    switch (_selectedSizeUnit) {
      case SizeUnit.b:
        bytes = val.round();
        break;
      case SizeUnit.kb:
        bytes = (val * 1024).round();
        break;
      case SizeUnit.mb:
        bytes = (val * 1024 * 1024).round();
        break;
      case SizeUnit.gb:
        bytes = (val * 1024 * 1024 * 1024).round();
        break;
    }
    _rule = _rule.copyWith(sizeValueBytes: bytes);
    _triggerChanged();
  }

  InputDecoration _buildInputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: context.textColorSecondary),
      hintStyle: TextStyle(color: context.textColorSecondary.withOpacity(0.5)),
      filled: true,
      fillColor: context.inputBg,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.inputBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showFileOptions = _rule.target == DeleteTarget.file || _rule.target == DeleteTarget.both;
    final showFolderOptions = _rule.target == DeleteTarget.folder || _rule.target == DeleteTarget.both;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Target & Range card
        Card(
          color: context.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '扫描与清理对象',
                  style: TextStyle(color: context.textColorPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),

                // Object Type selection
                Row(
                  children: [
                    Text('清理目标:', style: TextStyle(color: context.textColorSecondary)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<DeleteTarget>(
                        segments: const [
                          ButtonSegment<DeleteTarget>(
                            value: DeleteTarget.file,
                            label: Text('文件'),
                            icon: Icon(Icons.insert_drive_file, size: 16),
                          ),
                          ButtonSegment<DeleteTarget>(
                            value: DeleteTarget.folder,
                            label: Text('文件夹'),
                            icon: Icon(Icons.folder, size: 16),
                          ),
                          ButtonSegment<DeleteTarget>(
                            value: DeleteTarget.both,
                            label: Text('全部'),
                            icon: Icon(Icons.all_inclusive, size: 16),
                          ),
                        ],
                        selected: {_rule.target},
                        onSelectionChanged: (newSelection) {
                          setState(() {
                            // Turn off duplicate check if switching to folders only
                            bool dup = _rule.duplicateFilesOnly;
                            if (newSelection.first == DeleteTarget.folder) {
                              dup = false;
                            }
                            _rule = _rule.copyWith(
                              target: newSelection.first,
                              duplicateFilesOnly: dup,
                            );
                            _triggerChanged();
                          });
                        },
                        style: ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.red.withOpacity(0.2);
                            }
                            return null;
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.redAccent;
                            }
                            return null;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Recursive Scan switch
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '包含子文件夹 (递归扫描)',
                      style: TextStyle(color: context.textColorSecondary),
                    ),
                    Switch(
                      value: _recursive,
                      onChanged: (val) {
                        setState(() {
                          _recursive = val;
                          _triggerChanged();
                        });
                      },
                      activeColor: Colors.redAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 2. Filters card
        Card(
          color: context.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '高级筛选规则 (多条件取并集或交集配合)',
                  style: TextStyle(color: context.textColorPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 10),

                // Format constraint (Only if files selected)
                if (showFileOptions && !_rule.duplicateFilesOnly) ...[
                  TextField(
                    controller: _extController,
                    style: TextStyle(color: context.textColorPrimary),
                    decoration: _buildInputDecoration(
                      '特定格式后缀 (多个用逗号隔开)',
                      hint: '例如: png, jpg, log, tmp (留空匹配所有)',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // File/Folder name contains
                if (!_rule.duplicateFilesOnly) ...[
                  TextField(
                    controller: _nameController,
                    style: TextStyle(color: context.textColorPrimary),
                    decoration: _buildInputDecoration(
                      '名称包含特定文本',
                      hint: '输入匹配的文件/文件夹名称关键字',
                    ),
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    title: Text('区分大小写', style: TextStyle(color: context.textColorPrimary, fontSize: 14)),
                    value: _rule.caseSensitive,
                    activeColor: Colors.redAccent,
                    onChanged: (val) {
                      setState(() {
                        _rule = _rule.copyWith(caseSensitive: val ?? false);
                        _triggerChanged();
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                  Divider(color: context.borderColor, height: 16),
                ],

                // Size Filter Section
                if (!_rule.duplicateFilesOnly) ...[
                  Text('大小筛选:', style: TextStyle(color: context.textColorSecondary, fontSize: 14)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<SizeCondition>(
                          value: _rule.sizeCondition,
                          dropdownColor: context.cardBg,
                          style: TextStyle(color: context.textColorPrimary, fontSize: 14),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: SizeCondition.any, child: Text('不限大小')),
                            DropdownMenuItem(value: SizeCondition.greaterThan, child: Text('大于 (>)')),
                            DropdownMenuItem(value: SizeCondition.lessThan, child: Text('小于 (<)')),
                            DropdownMenuItem(value: SizeCondition.equalTo, child: Text('等于 (=)')),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _rule = _rule.copyWith(sizeCondition: val ?? SizeCondition.any);
                              _triggerChanged();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_rule.sizeCondition != SizeCondition.any) ...[
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _sizeValueController,
                            style: TextStyle(color: context.textColorPrimary, fontSize: 14),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                            decoration: _buildInputDecoration('数值'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<SizeUnit>(
                            value: _selectedSizeUnit,
                            dropdownColor: context.cardBg,
                            style: TextStyle(color: context.textColorPrimary, fontSize: 14),
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            items: SizeUnit.values.map((unit) {
                              return DropdownMenuItem(value: unit, child: Text(unit.name.toUpperCase()));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedSizeUnit = val;
                                  _updateSizeBytes();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  Divider(color: context.borderColor, height: 16),
                ],

                // Time Filter Section
                if (!_rule.duplicateFilesOnly) ...[
                  Text('修改时间筛选:', style: TextStyle(color: context.textColorSecondary, fontSize: 14)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<TimeCondition>(
                    value: _rule.timeCondition,
                    dropdownColor: context.cardBg,
                    style: TextStyle(color: context.textColorPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: TimeCondition.any, child: Text('不限修改时间')),
                      DropdownMenuItem(value: TimeCondition.beforeDate, child: Text('修改时间早于某日')),
                      DropdownMenuItem(value: TimeCondition.afterDate, child: Text('修改时间晚于某日')),
                      DropdownMenuItem(value: TimeCondition.olderThanDays, child: Text('修改时间已超过指定天数')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _rule = _rule.copyWith(timeCondition: val ?? TimeCondition.any);
                        _triggerChanged();
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  if (_rule.timeCondition == TimeCondition.beforeDate ||
                      _rule.timeCondition == TimeCondition.afterDate) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _rule.timeDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: context.isDarkMode
                                    ? const ColorScheme.dark(
                                        primary: Colors.redAccent,
                                        onPrimary: Colors.white,
                                        surface: Color(0xFF1E1E22),
                                        onSurface: Colors.white,
                                        )
                                    : const ColorScheme.light(
                                        primary: Colors.redAccent,
                                        onPrimary: Colors.white,
                                        surface: Colors.white,
                                        onSurface: Colors.black87,
                                      ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() {
                            _rule = _rule.copyWith(timeDate: picked);
                            _triggerChanged();
                          });
                        }
                      },
                      icon: const Icon(Icons.calendar_month, size: 16),
                      label: Text(
                        _rule.timeDate == null
                            ? '选择日期'
                            : '${_rule.timeDate!.year}-${_rule.timeDate!.month}-${_rule.timeDate!.day}',
                        style: TextStyle(color: context.textColorPrimary),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: context.inputBorderColor),
                      ),
                    ),
                  ],
                  if (_rule.timeCondition == TimeCondition.olderThanDays) ...[
                    TextField(
                      controller: _timeDaysController,
                      style: TextStyle(color: context.textColorPrimary, fontSize: 14),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _buildInputDecoration('输入天数'),
                    ),
                  ],
                  Divider(color: context.borderColor, height: 16),
                ],

                // Hash (MD5) filter (Only for files)
                if (showFileOptions && !_rule.duplicateFilesOnly) ...[
                  Text('MD5 哈希值特定匹配:', style: TextStyle(color: context.textColorSecondary, fontSize: 14)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _hashController,
                          style: TextStyle(color: context.textColorPrimary, fontSize: 13),
                          decoration: _buildInputDecoration('目标 MD5 哈希值', hint: '输入32位MD5哈希字符串'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isCalculatingMd5 ? null : _pickFileAndCalculateMd5,
                        icon: _isCalculatingMd5
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                              )
                            : const Icon(Icons.upload_file, size: 18),
                        label: Text(_isCalculatingMd5 ? '计算中' : '选择文件'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '提示：匹配哈希值会在此期间自动读取并计算文件MD5，可能会减慢大型文件的扫描预览。',
                    style: TextStyle(color: context.textColorSecondary, fontSize: 11),
                  ),
                  Divider(color: context.borderColor, height: 16),
                ],

                // Performance & Scan Settings
                Text('扫描与性能设置:', style: TextStyle(color: context.textColorSecondary, fontSize: 14)),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value: _rule.maxThreads,
                  dropdownColor: context.cardBg,
                  style: TextStyle(color: context.textColorPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: const OutlineInputBorder(),
                    labelText: '哈希计算并发线程数',
                    labelStyle: TextStyle(color: context.textColorSecondary, fontSize: 12),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('自适应 (根据磁盘类型自动选择)')),
                    DropdownMenuItem(value: 1, child: Text('单线程 (1 Isolate - 机械硬盘HDD推荐)')),
                    DropdownMenuItem(value: 2, child: Text('双线程 (2 Isolates)')),
                    DropdownMenuItem(value: 4, child: Text('4 线程并发 (4 Isolates)')),
                    DropdownMenuItem(value: 8, child: Text('8 线程并发 (8 Isolates)')),
                    DropdownMenuItem(value: 16, child: Text('16 线程并发 (16 Isolates)')),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _rule = _rule.copyWith(maxThreads: val ?? 0);
                      _triggerChanged();
                    });
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  '提示：程序默认会检测扫描目录所在的驱动器媒介类型。机械硬盘限制单线程以防磁头频繁寻道卡死，固态硬盘则会使用多线程跑满带宽。',
                  style: TextStyle(color: context.textColorSecondary, fontSize: 11),
                ),
                Divider(color: context.borderColor, height: 16),

                // Shortcut/Special Filters (Empty folder, Empty file, Duplicate Files)
                Text('常用快捷筛选 / 一键清理项:', style: TextStyle(color: context.textColorSecondary, fontSize: 14)),
                const SizedBox(height: 6),
                
                // Empty Files Option
                if (showFileOptions && !_rule.duplicateFilesOnly)
                  CheckboxListTile(
                    title: Text('仅筛选空文件 (0字节)', style: TextStyle(color: context.textColorPrimary, fontSize: 13)),
                    value: _rule.emptyFilesOnly,
                    activeColor: Colors.redAccent,
                    onChanged: (val) {
                      setState(() {
                        _rule = _rule.copyWith(emptyFilesOnly: val ?? false);
                        _triggerChanged();
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),

                // Empty Folders Option
                if (showFolderOptions && !_rule.duplicateFilesOnly)
                  CheckboxListTile(
                    title: Text('仅筛选空文件夹 (子内容为空)', style: TextStyle(color: context.textColorPrimary, fontSize: 13)),
                    value: _rule.emptyFoldersOnly,
                    activeColor: Colors.redAccent,
                    onChanged: (val) {
                      setState(() {
                        _rule = _rule.copyWith(emptyFoldersOnly: val ?? false);
                        _triggerChanged();
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),

                // Duplicate Files Option
                if (showFileOptions)
                  CheckboxListTile(
                    title: Text('仅筛选重复文件 (大小相同且MD5相同)', style: TextStyle(color: context.textColorPrimary, fontSize: 13)),
                    subtitle: Text('将扫描相同内容的文件，并默认勾选多余副本（保留修改时间最早的一份）', style: TextStyle(color: context.textColorSecondary, fontSize: 11)),
                    value: _rule.duplicateFilesOnly,
                    activeColor: Colors.redAccent,
                    onChanged: (val) {
                      setState(() {
                        _rule = _rule.copyWith(duplicateFilesOnly: val ?? false);
                        _triggerChanged();
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum SizeUnit { b, kb, mb, gb }
