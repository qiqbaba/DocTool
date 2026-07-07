import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/move_logic.dart';

class MoveRulePanel extends StatefulWidget {
  final MoveFilterRule initialRule;
  final bool initialRecursive;
  final String initialTargetDirPath;
  final ConflictStrategy initialConflictStrategy;
  final Function(MoveFilterRule rule, bool recursive, String targetDirPath, ConflictStrategy strategy) onChanged;

  const MoveRulePanel({
    super.key,
    required this.initialRule,
    required this.initialRecursive,
    required this.initialTargetDirPath,
    required this.initialConflictStrategy,
    required this.onChanged,
  });

  @override
  State<MoveRulePanel> createState() => _MoveRulePanelState();
}

class _MoveRulePanelState extends State<MoveRulePanel> {
  late MoveFilterRule _rule;
  late bool _recursive;
  late String _targetDirPath;
  late ConflictStrategy _conflictStrategy;

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
    _targetDirPath = widget.initialTargetDirPath;
    _conflictStrategy = widget.initialConflictStrategy;

    // Initialize controller texts
    _extController.text = _rule.extensionFilter;
    _nameController.text = _rule.nameContains;
    
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
          targetHashSize: null,
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
        final md5Hash = await MoveLogic.calculateFileMd5(file);
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
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    }
  }

  void _triggerChanged() {
    widget.onChanged(_rule, _recursive, _targetDirPath, _conflictStrategy);
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

  Future<void> _selectTargetDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择移动的目标文件夹',
    );
    if (path != null && path.isNotEmpty) {
      setState(() {
        _targetDirPath = path;
      });
      _triggerChanged();
    }
  }

  InputDecoration _buildInputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.grey),
      hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
      filled: true,
      fillColor: const Color(0xFF1E1E22),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2C2C35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.orangeAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showFileOptions = _rule.target == MoveTarget.file || _rule.target == MoveTarget.both;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 0. Destination Selector Card (Highest Priority for Move)
        Card(
          color: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF232329)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '移动目标目录',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E22),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF2C2C35)),
                        ),
                        child: Text(
                          _targetDirPath.isEmpty ? '未选择目标文件夹，请点击右侧选择' : _targetDirPath,
                          style: TextStyle(
                            color: _targetDirPath.isEmpty ? Colors.grey : Colors.orangeAccent,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _selectTargetDirectory,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('选择'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 1. Target & Range card
        Card(
          color: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF232329)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '扫描与过滤对象',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 12),

                // Object Type selection
                Row(
                  children: [
                    const Text('移动目标:', style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<MoveTarget>(
                        segments: const [
                          ButtonSegment<MoveTarget>(
                            value: MoveTarget.file,
                            label: Text('文件'),
                            icon: Icon(Icons.insert_drive_file, size: 16),
                          ),
                          ButtonSegment<MoveTarget>(
                            value: MoveTarget.folder,
                            label: Text('文件夹'),
                            icon: Icon(Icons.folder, size: 16),
                          ),
                          ButtonSegment<MoveTarget>(
                            value: MoveTarget.both,
                            label: Text('全部'),
                            icon: Icon(Icons.all_inclusive, size: 16),
                          ),
                        ],
                        selected: {_rule.target},
                        onSelectionChanged: (newSelection) {
                          setState(() {
                            bool dup = _rule.duplicateFilesOnly;
                            if (newSelection.first == MoveTarget.folder) {
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
                              return Colors.orange.withOpacity(0.2);
                            }
                            return null;
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.orangeAccent;
                            }
                            return null;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Recursive Scan switch
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '包含子文件夹 (递归扫描)',
                      style: TextStyle(color: Colors.grey),
                    ),
                    Switch(
                      value: _recursive,
                      onChanged: (val) {
                        setState(() {
                          _recursive = val;
                          _triggerChanged();
                        });
                      },
                      activeColor: Colors.orangeAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 2. Move Options Card
        Card(
          color: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF232329)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '同名冲突与目录结构设置',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 12),
                
                // Conflict Strategy Dropdown
                Row(
                  children: [
                    const Text('同名冲突时:', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<ConflictStrategy>(
                        value: _conflictStrategy,
                        dropdownColor: const Color(0xFF1E1E22),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: ConflictStrategy.autoRename,
                            child: Text('自动重命名 (filename (1).ext)'),
                          ),
                          DropdownMenuItem(
                            value: ConflictStrategy.overwrite,
                            child: Text('覆盖 (替换目标文件)'),
                          ),
                          DropdownMenuItem(
                            value: ConflictStrategy.skip,
                            child: Text('跳过 (不移动)'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _conflictStrategy = val;
                              _triggerChanged();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Keep Structure option
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '保持源文件夹目录结构',
                            style: TextStyle(color: Colors.grey),
                          ),
                          Text(
                            '开启则按源相对层级移动；关闭则把文件拍平移动到目标根目录',
                            style: TextStyle(color: Colors.grey, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _rule.keepStructure,
                      onChanged: (val) {
                        setState(() {
                          _rule = _rule.copyWith(keepStructure: val);
                          _triggerChanged();
                        });
                      },
                      activeColor: Colors.orangeAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 3. Filters card
        Card(
          color: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF232329)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '文件与文件夹筛选条件',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 16),

                // Format constraint (Only if files selected)
                if (showFileOptions && !_rule.duplicateFilesOnly) ...[
                  TextField(
                    controller: _extController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _buildInputDecoration(
                      '特定格式后缀 (多个用逗号隔开)',
                      hint: '例如: png, jpg, log, tmp (留空匹配所有)',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // File/Folder name contains
                if (!_rule.duplicateFilesOnly) ...[
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _buildInputDecoration(
                      '名称包含特定文本',
                      hint: '输入匹配的文件/文件夹名称关键字',
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('区分大小写', style: TextStyle(color: Colors.white, fontSize: 14)),
                    value: _rule.caseSensitive,
                    activeColor: Colors.orangeAccent,
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
                  const Divider(color: Color(0xFF232329), height: 24),
                ],

                // Size Filter Section
                if (!_rule.duplicateFilesOnly) ...[
                  const Text('大小筛选:', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<SizeCondition>(
                          value: _rule.sizeCondition,
                          dropdownColor: const Color(0xFF1E1E22),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
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
                            style: const TextStyle(color: Colors.white, fontSize: 14),
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
                            dropdownColor: const Color(0xFF1E1E22),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
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
                  const Divider(color: Color(0xFF232329), height: 24),
                ],

                // Time Filter Section
                if (!_rule.duplicateFilesOnly) ...[
                  const Text('修改时间筛选:', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<TimeCondition>(
                    value: _rule.timeCondition,
                    dropdownColor: const Color(0xFF1E1E22),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: TimeCondition.any, child: Text('不限修改时间')),
                      DropdownMenuItem(value: TimeCondition.beforeDate, child: Text('早于指定日期')),
                      DropdownMenuItem(value: TimeCondition.afterDate, child: Text('晚于指定日期')),
                      DropdownMenuItem(value: TimeCondition.olderThanDays, child: Text('旧于指定天数')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _rule = _rule.copyWith(timeCondition: val ?? TimeCondition.any);
                        _triggerChanged();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  if (_rule.timeCondition == TimeCondition.beforeDate || _rule.timeCondition == TimeCondition.afterDate) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _rule.timeDate == null
                                ? '未选择日期'
                                : '选定日期: ${_rule.timeDate!.year}-${_rule.timeDate!.month}-${_rule.timeDate!.day}',
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _rule.timeDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setState(() {
                                _rule = _rule.copyWith(timeDate: picked);
                                _triggerChanged();
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C2C35)),
                          child: const Text('选择日期', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                  if (_rule.timeCondition == TimeCondition.olderThanDays) ...[
                    TextField(
                      controller: _timeDaysController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _buildInputDecoration('天数阈值', hint: '例如：30'),
                    ),
                  ],
                  const Divider(color: Color(0xFF232329), height: 24),
                ],

                // Hash MD5 Filter Section
                if (showFileOptions && !_rule.duplicateFilesOnly) ...[
                  const Text('MD5 哈希值特定匹配:', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _hashController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
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
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent),
                              )
                            : const Icon(Icons.upload_file, size: 18),
                        label: Text(_isCalculatingMd5 ? '计算中' : '选择文件'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFF232329), height: 24),
                ],

                // Shortcut / Special Filters Section
                const Text('快捷/组合筛选 (包含上述类型限制):', style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('仅匹配空文件 (0 字节文件)', style: TextStyle(color: Colors.white, fontSize: 13)),
                  value: _rule.emptyFilesOnly,
                  activeColor: Colors.orangeAccent,
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
                CheckboxListTile(
                  title: const Text('仅匹配空文件夹 (不含子文件)', style: TextStyle(color: Colors.white, fontSize: 13)),
                  value: _rule.emptyFoldersOnly,
                  activeColor: Colors.orangeAccent,
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
                if (showFileOptions)
                  CheckboxListTile(
                    title: const Text('仅匹配重复文件 (MD5一致，自动保留最早修改的一份)', style: TextStyle(color: Colors.white, fontSize: 13)),
                    value: _rule.duplicateFilesOnly,
                    activeColor: Colors.orangeAccent,
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
