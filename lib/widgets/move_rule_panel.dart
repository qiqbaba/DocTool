import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/move_logic.dart';
import '../utils/theme_helper.dart';

class MoveRulePanel extends StatefulWidget {
  final MoveFilterRule initialRule;
  final bool initialRecursive;
  final String initialTargetDirPath;
  final ConflictStrategy initialConflictStrategy;
  final Function(MoveFilterRule rule, bool recursive, String targetDirPath,
      ConflictStrategy strategy) onChanged;

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
  final TextEditingController _deleteSizeController = TextEditingController();

  SizeUnit _selectedSizeUnit = SizeUnit.kb;
  SizeUnit _deleteSizeUnit = SizeUnit.kb;
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
        _sizeValueController.text =
            (bytes / (1024 * 1024 * 1024)).toStringAsFixed(0);
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

    final limit = _rule.deleteSizeLimitBytes;
    if (limit >= 1024 * 1024 && limit % (1024 * 1024) == 0) {
      _deleteSizeController.text = (limit / (1024 * 1024)).toStringAsFixed(0);
      _deleteSizeUnit = SizeUnit.mb;
    } else if (limit >= 1024 && limit % 1024 == 0) {
      _deleteSizeController.text = (limit / 1024).toStringAsFixed(0);
      _deleteSizeUnit = SizeUnit.kb;
    } else {
      _deleteSizeController.text = limit.toString();
      _deleteSizeUnit = SizeUnit.b;
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
    _deleteSizeController.addListener(() {
      _updateDeleteSizeBytes();
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
    _deleteSizeController.dispose();
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

  void _updateDeleteSizeBytes() {
    final val = double.tryParse(_deleteSizeController.text) ?? 0.0;
    int bytes = 0;
    switch (_deleteSizeUnit) {
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
    _rule = _rule.copyWith(deleteSizeLimitBytes: bytes);
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
      labelStyle: TextStyle(color: context.textColorSecondary),
      hintStyle:
          TextStyle(color: context.textColorSecondary.withValues(alpha: 0.5)),
      filled: true,
      fillColor: context.inputBg,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.inputBorderColor),
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
    final showFileOptions =
        _rule.target == MoveTarget.file || _rule.target == MoveTarget.both;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 0. Destination Selector Card (Highest Priority for Move)
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
                  '移动目标目录与模式',
                  style: TextStyle(
                      color: context.textColorPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '扁平化子孙文件到根目录并清理空文件夹',
                            style: TextStyle(
                                color: context.textColorPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '将子孙文件夹中的所有文件移动 to 源目录根路径，并删除空文件夹',
                            style: TextStyle(
                                color: context.textColorSecondary,
                                fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _rule.flattenToRoot,
                      onChanged: (val) {
                        setState(() {
                          _rule = _rule.copyWith(
                            flattenToRoot: val,
                            target: val ? MoveTarget.file : _rule.target,
                            keepStructure: val ? false : _rule.keepStructure,
                          );
                          _triggerChanged();
                        });
                      },
                      activeThumbColor: Colors.orangeAccent,
                    ),
                  ],
                ),
                Divider(color: context.borderColor, height: 16),
                Opacity(
                  opacity: _rule.flattenToRoot ? 0.5 : 1.0,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: context.inputBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.inputBorderColor),
                          ),
                          child: Text(
                            _rule.flattenToRoot
                                ? '扁平化模式：已自动设定目标目录为源目录'
                                : (_targetDirPath.isEmpty
                                    ? '未选择目标文件夹，请点击右侧选择'
                                    : _targetDirPath),
                            style: TextStyle(
                              color: _rule.flattenToRoot
                                  ? context.textColorSecondary
                                  : (_targetDirPath.isEmpty
                                      ? context.textColorSecondary
                                      : Colors.orangeAccent),
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
                        onPressed:
                            _rule.flattenToRoot ? null : _selectTargetDirectory,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('选择'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: context.isDarkMode
                              ? Colors.grey[800]
                              : Colors.grey[300],
                          disabledForegroundColor: context.isDarkMode
                              ? Colors.grey[600]
                              : Colors.grey[500],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

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
                  '扫描与过滤对象',
                  style: TextStyle(
                      color: context.textColorPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                const SizedBox(height: 8),

                // Object Type selection
                Opacity(
                  opacity: _rule.flattenToRoot ? 0.5 : 1.0,
                  child: Row(
                    children: [
                      Text('移动目标:',
                          style: TextStyle(color: context.textColorSecondary)),
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
                          onSelectionChanged: _rule.flattenToRoot
                              ? null
                              : (newSelection) {
                                  setState(() {
                                    bool dup = _rule.duplicateFilesOnly;
                                    if (newSelection.first ==
                                        MoveTarget.folder) {
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
                            backgroundColor:
                                WidgetStateProperty.resolveWith<Color?>(
                                    (states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.orange.withValues(alpha: 0.2);
                              }
                              return null;
                            }),
                            foregroundColor:
                                WidgetStateProperty.resolveWith<Color?>(
                                    (states) {
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
                ),
                const SizedBox(height: 8),

                // Recursive Scan switch
                Opacity(
                  opacity: _rule.flattenToRoot ? 0.5 : 1.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '包含子文件夹 (递归扫描)',
                        style: TextStyle(color: Colors.grey),
                      ),
                      Switch(
                        value: _rule.flattenToRoot ? true : _recursive,
                        onChanged: _rule.flattenToRoot
                            ? null
                            : (val) {
                                setState(() {
                                  _recursive = val;
                                  _triggerChanged();
                                });
                              },
                        activeThumbColor: Colors.orangeAccent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // 2. Move Options Card
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
                  '同名冲突与目录结构设置',
                  style: TextStyle(
                      color: context.textColorPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                const SizedBox(height: 8),

                // Conflict Strategy Dropdown
                Row(
                  children: [
                    Text('同名冲突时:',
                        style: TextStyle(
                            color: context.textColorSecondary, fontSize: 14)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<ConflictStrategy>(
                        initialValue: _conflictStrategy,
                        dropdownColor: context.cardBg,
                        style: TextStyle(
                            color: context.textColorPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                const SizedBox(height: 8),

                // Keep Structure option
                Opacity(
                  opacity: _rule.flattenToRoot ? 0.5 : 1.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '保持源文件夹目录结构',
                              style:
                                  TextStyle(color: context.textColorSecondary),
                            ),
                            Text(
                              '开启则按源相对层级移动；关闭则把文件拍平移动到目标根目录',
                              style: TextStyle(
                                  color: context.textColorSecondary,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value:
                            _rule.flattenToRoot ? false : _rule.keepStructure,
                        onChanged: _rule.flattenToRoot
                            ? null
                            : (val) {
                                setState(() {
                                  _rule = _rule.copyWith(keepStructure: val);
                                  _triggerChanged();
                                });
                              },
                        activeThumbColor: Colors.orangeAccent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // 3. Filters card
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
                  '文件与文件夹筛选条件',
                  style: TextStyle(
                      color: context.textColorPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
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
                    title: Text('区分大小写',
                        style: TextStyle(
                            color: context.textColorPrimary, fontSize: 14)),
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
                  Divider(color: context.borderColor, height: 16),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<SizeCondition>(
                          initialValue: _rule.sizeCondition,
                          dropdownColor: context.cardBg,
                          style: TextStyle(
                              color: context.textColorPrimary, fontSize: 14),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: SizeCondition.any, child: Text('不限大小')),
                            DropdownMenuItem(
                                value: SizeCondition.greaterThan,
                                child: Text('大于 (>)')),
                            DropdownMenuItem(
                                value: SizeCondition.lessThan,
                                child: Text('小于 (<)')),
                            DropdownMenuItem(
                                value: SizeCondition.equalTo,
                                child: Text('等于 (=)')),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _rule = _rule.copyWith(
                                  sizeCondition: val ?? SizeCondition.any);
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
                            style: TextStyle(
                                color: context.textColorPrimary, fontSize: 14),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d*'))
                            ],
                            decoration: _buildInputDecoration('数值'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<SizeUnit>(
                            initialValue: _selectedSizeUnit,
                            dropdownColor: context.cardBg,
                            style: TextStyle(
                                color: context.textColorPrimary, fontSize: 14),
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            items: SizeUnit.values.map((unit) {
                              return DropdownMenuItem(
                                  value: unit,
                                  child: Text(unit.name.toUpperCase()));
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
                  Divider(color: context.borderColor, height: 24),
                ],

                // Time Filter Section
                if (!_rule.duplicateFilesOnly) ...[
                  Text('修改时间筛选:',
                      style: TextStyle(
                          color: context.textColorSecondary, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<TimeCondition>(
                    initialValue: _rule.timeCondition,
                    dropdownColor: context.cardBg,
                    style: TextStyle(
                        color: context.textColorPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: TimeCondition.any, child: Text('不限修改时间')),
                      DropdownMenuItem(
                          value: TimeCondition.beforeDate,
                          child: Text('早于指定日期')),
                      DropdownMenuItem(
                          value: TimeCondition.afterDate,
                          child: Text('晚于指定日期')),
                      DropdownMenuItem(
                          value: TimeCondition.olderThanDays,
                          child: Text('旧于指定天数')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _rule = _rule.copyWith(
                            timeCondition: val ?? TimeCondition.any);
                        _triggerChanged();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  if (_rule.timeCondition == TimeCondition.beforeDate ||
                      _rule.timeCondition == TimeCondition.afterDate) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _rule.timeDate == null
                                ? '未选择日期'
                                : '选定日期: ${_rule.timeDate!.year}-${_rule.timeDate!.month}-${_rule.timeDate!.day}',
                            style: TextStyle(
                                color: context.textColorPrimary, fontSize: 13),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _rule.timeDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: context.isDarkMode
                                        ? const ColorScheme.dark(
                                            primary: Colors.orangeAccent,
                                            onPrimary: Colors.black,
                                            surface: Color(0xFF1E1E22),
                                            onSurface: Colors.white,
                                          )
                                        : const ColorScheme.light(
                                            primary: Colors.orangeAccent,
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.inputBg,
                            foregroundColor: context.textColorPrimary,
                          ),
                          child: const Text('选择日期'),
                        ),
                      ],
                    ),
                  ],
                  if (_rule.timeCondition == TimeCondition.olderThanDays) ...[
                    TextField(
                      controller: _timeDaysController,
                      style: TextStyle(color: context.textColorPrimary),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _buildInputDecoration('天数阈值', hint: '例如：30'),
                    ),
                  ],
                  Divider(color: context.borderColor, height: 24),
                ],

                // Hash MD5 Filter Section
                if (showFileOptions && !_rule.duplicateFilesOnly) ...[
                  Text('MD5 哈希值特定匹配:',
                      style: TextStyle(
                          color: context.textColorSecondary, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _hashController,
                          style: TextStyle(
                              color: context.textColorPrimary, fontSize: 13),
                          decoration: _buildInputDecoration('目标 MD5 哈希值',
                              hint: '输入32位MD5哈希字符串'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed:
                            _isCalculatingMd5 ? null : _pickFileAndCalculateMd5,
                        icon: _isCalculatingMd5
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.orangeAccent),
                              )
                            : const Icon(Icons.upload_file, size: 18),
                        label: Text(_isCalculatingMd5 ? '计算中' : '选择文件'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                  Divider(color: context.borderColor, height: 24),
                ],

                // Shortcut / Special Filters Section
                Text('快捷/组合筛选 (包含上述类型限制):',
                    style: TextStyle(
                        color: context.textColorSecondary, fontSize: 14)),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: Text('仅匹配空文件 (0 字节文件)',
                      style: TextStyle(
                          color: context.textColorPrimary, fontSize: 13)),
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
                  title: Text('仅匹配空文件夹 (不含子文件)',
                      style: TextStyle(
                          color: context.textColorPrimary, fontSize: 13)),
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
                    title: Text('仅匹配重复文件 (MD5一致，自动保留最早修改的一份)',
                        style: TextStyle(
                            color: context.textColorPrimary, fontSize: 13)),
                    value: _rule.duplicateFilesOnly,
                    activeColor: Colors.orangeAccent,
                    onChanged: (val) {
                      setState(() {
                        _rule =
                            _rule.copyWith(duplicateFilesOnly: val ?? false);
                        _triggerChanged();
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                CheckboxListTile(
                  title: Text('移动时自动删除指定大小的小垃圾文件',
                      style: TextStyle(
                          color: context.textColorPrimary, fontSize: 13)),
                  subtitle: Text('符合设定大小的小文件在移动时会被直接删除而不搬移',
                      style: TextStyle(
                          color: context.textColorSecondary, fontSize: 11)),
                  value: _rule.deleteSpecifiedSizeFiles,
                  activeColor: Colors.orangeAccent,
                  onChanged: (val) {
                    setState(() {
                      _rule = _rule.copyWith(
                          deleteSpecifiedSizeFiles: val ?? false);
                      _triggerChanged();
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
                if (_rule.deleteSpecifiedSizeFiles) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('大小限值: 小于 ',
                          style: TextStyle(
                              color: context.textColorSecondary, fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _deleteSizeController,
                          style: TextStyle(
                              color: context.textColorPrimary, fontSize: 13),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'))
                          ],
                          decoration: _buildInputDecoration('数值'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<SizeUnit>(
                          initialValue: _deleteSizeUnit,
                          dropdownColor: context.cardBg,
                          style: TextStyle(
                              color: context.textColorPrimary, fontSize: 13),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: SizeUnit.b, child: Text('B')),
                            DropdownMenuItem(
                                value: SizeUnit.kb, child: Text('KB')),
                            DropdownMenuItem(
                                value: SizeUnit.mb, child: Text('MB')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _deleteSizeUnit = val;
                                _updateDeleteSizeBytes();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum SizeUnit { b, kb, mb, gb }
