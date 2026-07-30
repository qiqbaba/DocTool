import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/rename_logic.dart';
import '../utils/theme_helper.dart';

class RenameRulePanel extends StatefulWidget {
  final RenameRule initialRule;
  final bool initialIsTargetFile;
  final bool initialIsTargetFolder;
  final bool initialRecursive;
  final String initialExtensionFilter;
  final Function(
    RenameRule rule,
    bool isTargetFile,
    bool isTargetFolder,
    bool recursive,
    String extensionFilter,
  ) onChanged;

  const RenameRulePanel({
    super.key,
    required this.initialRule,
    required this.initialIsTargetFile,
    required this.initialIsTargetFolder,
    required this.initialRecursive,
    required this.initialExtensionFilter,
    required this.onChanged,
  });

  @override
  State<RenameRulePanel> createState() => _RenameRulePanelState();
}

class _RenameRulePanelState extends State<RenameRulePanel>
    with SingleTickerProviderStateMixin {
  late RenameRule _rule;
  late RenameTarget _target;
  late bool _recursive;
  late String _extensionFilter;

  bool get _isTargetFile =>
      _target == RenameTarget.file || _target == RenameTarget.both;
  bool get _isTargetFolder =>
      _target == RenameTarget.folder || _target == RenameTarget.both;

  // Controllers
  final TextEditingController _extController = TextEditingController();
  final TextEditingController _insertTextController = TextEditingController();
  final TextEditingController _insertIndexController = TextEditingController();
  final TextEditingController _insertSeparatorCustomController =
      TextEditingController();
  final TextEditingController _deleteMatchController = TextEditingController();
  final TextEditingController _deleteCountController = TextEditingController();
  final TextEditingController _deleteStartController = TextEditingController();
  final TextEditingController _deleteEndController = TextEditingController();
  final TextEditingController _deleteAnchorController = TextEditingController();
  final TextEditingController _parentDirIndexController =
      TextEditingController();
  final TextEditingController _parentDirSeparatorCustomController =
      TextEditingController();

  late TabController _tabController;
  late String _selectedInsertSepType;
  late String _selectedParentDirSepType;

  @override
  void initState() {
    super.initState();
    _rule = widget.initialRule;
    if (widget.initialIsTargetFile && widget.initialIsTargetFolder) {
      _target = RenameTarget.both;
    } else if (widget.initialIsTargetFolder) {
      _target = RenameTarget.folder;
    } else {
      _target = RenameTarget.file;
    }
    _recursive = widget.initialRecursive;
    _extensionFilter = widget.initialExtensionFilter;

    _tabController = TabController(length: 3, vsync: this);

    // Set initial controller values
    _extController.text = _extensionFilter;
    _insertTextController.text = _rule.insertRule.text;
    _insertIndexController.text = _rule.insertRule.customIndex.toString();

    // Set separator states and controllers
    final initialInsertSep = _rule.insertRule.separator;
    if (['', '-', '_', ' ', '.'].contains(initialInsertSep)) {
      _selectedInsertSepType = initialInsertSep;
      _insertSeparatorCustomController.text = '';
    } else {
      _selectedInsertSepType = 'custom';
      _insertSeparatorCustomController.text = initialInsertSep;
    }

    final initialParentDirSep = _rule.parentDirRule.separator;
    if (['', '-', '_', ' ', '.'].contains(initialParentDirSep)) {
      _selectedParentDirSepType = initialParentDirSep;
      _parentDirSeparatorCustomController.text = '';
    } else {
      _selectedParentDirSepType = 'custom';
      _parentDirSeparatorCustomController.text = initialParentDirSep;
    }

    _deleteMatchController.text = _rule.deleteRule.matchText;
    _deleteCountController.text = _rule.deleteRule.count.toString();
    _deleteStartController.text = _rule.deleteRule.startIndex.toString();
    _deleteEndController.text = _rule.deleteRule.endIndex.toString();
    _deleteAnchorController.text = _rule.deleteRule.anchorChar;
    _parentDirIndexController.text = _rule.parentDirRule.customIndex.toString();

    // Setup update listeners
    _extController.addListener(() {
      _extensionFilter = _extController.text;
      _triggerChanged();
    });
    _insertTextController.addListener(() {
      _rule = _rule.copyWith(
        insertRule: _rule.insertRule.copyWith(text: _insertTextController.text),
      );
      _triggerChanged();
    });
    _insertIndexController.addListener(() {
      final val = int.tryParse(_insertIndexController.text) ?? 0;
      _rule = _rule.copyWith(
        insertRule: _rule.insertRule.copyWith(customIndex: val),
      );
      _triggerChanged();
    });
    _insertSeparatorCustomController.addListener(() {
      if (_selectedInsertSepType == 'custom') {
        _rule = _rule.copyWith(
          insertRule: _rule.insertRule
              .copyWith(separator: _insertSeparatorCustomController.text),
        );
        _triggerChanged();
      }
    });
    _deleteMatchController.addListener(() {
      _rule = _rule.copyWith(
        deleteRule:
            _rule.deleteRule.copyWith(matchText: _deleteMatchController.text),
      );
      _triggerChanged();
    });
    _deleteCountController.addListener(() {
      final val = int.tryParse(_deleteCountController.text) ?? 0;
      _rule = _rule.copyWith(
        deleteRule: _rule.deleteRule.copyWith(count: val),
      );
      _triggerChanged();
    });
    _deleteStartController.addListener(() {
      final val = int.tryParse(_deleteStartController.text) ?? 0;
      _rule = _rule.copyWith(
        deleteRule: _rule.deleteRule.copyWith(startIndex: val),
      );
      _triggerChanged();
    });
    _deleteEndController.addListener(() {
      final val = int.tryParse(_deleteEndController.text) ?? 0;
      _rule = _rule.copyWith(
        deleteRule: _rule.deleteRule.copyWith(endIndex: val),
      );
      _triggerChanged();
    });
    _deleteAnchorController.addListener(() {
      _rule = _rule.copyWith(
        deleteRule:
            _rule.deleteRule.copyWith(anchorChar: _deleteAnchorController.text),
      );
      _triggerChanged();
    });
    _parentDirIndexController.addListener(() {
      final val = int.tryParse(_parentDirIndexController.text) ?? 0;
      _rule = _rule.copyWith(
        parentDirRule: _rule.parentDirRule.copyWith(customIndex: val),
      );
      _triggerChanged();
    });
    _parentDirSeparatorCustomController.addListener(() {
      if (_selectedParentDirSepType == 'custom') {
        _rule = _rule.copyWith(
          parentDirRule: _rule.parentDirRule
              .copyWith(separator: _parentDirSeparatorCustomController.text),
        );
        _triggerChanged();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _extController.dispose();
    _insertTextController.dispose();
    _insertIndexController.dispose();
    _insertSeparatorCustomController.dispose();
    _deleteMatchController.dispose();
    _deleteCountController.dispose();
    _deleteStartController.dispose();
    _deleteEndController.dispose();
    _deleteAnchorController.dispose();
    _parentDirIndexController.dispose();
    _parentDirSeparatorCustomController.dispose();
    super.dispose();
  }

  void _triggerChanged() {
    widget.onChanged(
        _rule, _isTargetFile, _isTargetFolder, _recursive, _extensionFilter);
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
        borderSide: const BorderSide(color: Colors.indigo, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _buildSwitchHeader(
      String title, bool val, ValueChanged<bool> onToggle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.textColorPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Switch(
          value: val,
          onChanged: onToggle,
          activeThumbColor: Colors.indigoAccent,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Target & Range selection
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
                  '重命名范围',
                  style: TextStyle(
                      color: context.textColorPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                const SizedBox(height: 8),

                // Object Type Segment
                Row(
                  children: [
                    Text('对象类型:',
                        style: TextStyle(color: context.textColorSecondary)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<RenameTarget>(
                        segments: const [
                          ButtonSegment<RenameTarget>(
                            value: RenameTarget.file,
                            label: Text('文件'),
                            icon: Icon(Icons.insert_drive_file, size: 16),
                          ),
                          ButtonSegment<RenameTarget>(
                            value: RenameTarget.folder,
                            label: Text('文件夹'),
                            icon: Icon(Icons.folder, size: 16),
                          ),
                          ButtonSegment<RenameTarget>(
                            value: RenameTarget.both,
                            label: Text('全部'),
                            icon: Icon(Icons.all_inclusive, size: 16),
                          ),
                        ],
                        selected: {_target},
                        onSelectionChanged: (newSelection) {
                          setState(() {
                            _target = newSelection.first;
                            _triggerChanged();
                          });
                        },
                        style: ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.indigo.withValues(alpha: 0.2);
                            }
                            return null;
                          }),
                          foregroundColor:
                              WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.indigoAccent;
                            }
                            return null;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Recursive Switch
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      (_isTargetFile && _isTargetFolder)
                          ? '包含子孙文件与文件夹 (递归)'
                          : (_isTargetFile ? '包含子孙文件 (递归)' : '包含子孙文件夹 (递归)'),
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
                      activeThumbColor: Colors.indigoAccent,
                    ),
                  ],
                ),

                // Extension filter (Only for files)
                if (_isTargetFile) ...[
                  const SizedBox(height: 6),
                  TextField(
                    controller: _extController,
                    style: TextStyle(color: context.textColorPrimary),
                    decoration: _buildInputDecoration(
                      '限制格式 (多个格式用逗号隔开)',
                      hint: '例如: png, jpg, mp4 (留空或 * 代表所有文件)',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Tab header for Rules
        TabBar(
          controller: _tabController,
          labelColor: Colors.indigoAccent,
          unselectedLabelColor: context.textColorSecondary,
          indicatorColor: Colors.indigoAccent,
          tabs: const [
            Tab(text: '插入文本', icon: Icon(Icons.add_circle_outline)),
            Tab(text: '删除文本', icon: Icon(Icons.remove_circle_outline)),
            Tab(text: '插入父目录名', icon: Icon(Icons.folder_shared_outlined)),
          ],
        ),
        const SizedBox(height: 10),

        // Tab body for Rules
        SizedBox(
          height: 380,
          child: TabBarView(
            controller: _tabController,
            children: [
              // 1. Insert Text Tab
              _buildInsertTab(),
              // 2. Delete Text Tab
              _buildDeleteTab(),
              // 3. Parent Directory Name Tab
              _buildParentDirTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInsertTab() {
    final ins = _rule.insertRule;
    return Card(
      color: context.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          shrinkWrap: true,
          children: [
            _buildSwitchHeader('启用插入规则', ins.enabled, (val) {
              setState(() {
                _rule = _rule.copyWith(insertRule: ins.copyWith(enabled: val));
                _triggerChanged();
              });
            }),
            const SizedBox(height: 8),
            if (ins.enabled) ...[
              TextField(
                controller: _insertTextController,
                style: TextStyle(color: context.textColorPrimary),
                decoration: _buildInputDecoration('插入内容', hint: '输入要插入的文本'),
              ),
              const SizedBox(height: 10),
              _buildSeparatorSection(
                selectedType: _selectedInsertSepType,
                customController: _insertSeparatorCustomController,
                onTypeChanged: (type) {
                  setState(() {
                    _selectedInsertSepType = type;
                    final newSep = type == 'custom'
                        ? _insertSeparatorCustomController.text
                        : type;
                    _rule = _rule.copyWith(
                      insertRule: _rule.insertRule.copyWith(separator: newSep),
                    );
                    _triggerChanged();
                  });
                },
              ),
              const SizedBox(height: 10),
              Text('插入位置:',
                  style: TextStyle(color: context.textColorSecondary)),
              const SizedBox(height: 6),
              SegmentedButton<InsertPosition>(
                segments: const [
                  ButtonSegment(value: InsertPosition.start, label: Text('开头')),
                  ButtonSegment(value: InsertPosition.end, label: Text('结尾')),
                  ButtonSegment(
                      value: InsertPosition.custom, label: Text('自定义')),
                ],
                selected: {ins.position},
                onSelectionChanged: (val) {
                  setState(() {
                    _rule = _rule.copyWith(
                        insertRule: ins.copyWith(position: val.first));
                    _triggerChanged();
                  });
                },
                style: ButtonStyle(
                  backgroundColor:
                      WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.indigo.withValues(alpha: 0.2);
                    }
                    return null;
                  }),
                  foregroundColor:
                      WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.indigoAccent;
                    }
                    return null;
                  }),
                ),
              ),
              if (ins.position == InsertPosition.custom) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _insertIndexController,
                  style: TextStyle(color: context.textColorPrimary),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _buildInputDecoration('插入位置索引 (0-based)',
                      hint: '例如: 3 表示在第3个字符处插入'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteTab() {
    final del = _rule.deleteRule;
    return Card(
      color: context.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          shrinkWrap: true,
          children: [
            _buildSwitchHeader('启用删除规则', del.enabled, (val) {
              setState(() {
                _rule = _rule.copyWith(deleteRule: del.copyWith(enabled: val));
                _triggerChanged();
              });
            }),
            const SizedBox(height: 8),
            if (del.enabled) ...[
              Text('删除模式:',
                  style: TextStyle(color: context.textColorSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<DeleteMode>(
                initialValue: del.mode,
                dropdownColor: context.cardBg,
                style: TextStyle(color: context.textColorPrimary),
                decoration: _buildInputDecoration('选择删除模式'),
                items: const [
                  DropdownMenuItem(
                      value: DeleteMode.match, child: Text('匹配内容删除')),
                  DropdownMenuItem(
                      value: DeleteMode.rangeEnds, child: Text('开头/结尾字符删除')),
                  DropdownMenuItem(
                      value: DeleteMode.rangeCustom, child: Text('自定义区间删除')),
                  DropdownMenuItem(
                      value: DeleteMode.anchor, child: Text('定位字符前后删除')),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    setState(() {
                      _rule =
                          _rule.copyWith(deleteRule: del.copyWith(mode: mode));
                      _triggerChanged();
                    });
                  }
                },
              ),
              const SizedBox(height: 10),

              // 1. Match Mode Inputs
              if (del.mode == DeleteMode.match) ...[
                TextField(
                  controller: _deleteMatchController,
                  style: TextStyle(color: context.textColorPrimary),
                  decoration:
                      _buildInputDecoration('要删除的内容', hint: '输入被匹配的关键字'),
                ),
              ],

              // 2. Range Ends Mode Inputs
              if (del.mode == DeleteMode.rangeEnds) ...[
                Row(
                  children: [
                    Text('方向:',
                        style: TextStyle(color: context.textColorSecondary)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('删除开头')),
                          ButtonSegment(value: false, label: Text('删除结尾')),
                        ],
                        selected: {del.fromStart},
                        onSelectionChanged: (val) {
                          setState(() {
                            _rule = _rule.copyWith(
                                deleteRule: del.copyWith(fromStart: val.first));
                            _triggerChanged();
                          });
                        },
                        style: ButtonStyle(
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.indigo.withValues(alpha: 0.2);
                            }
                            return null;
                          }),
                          foregroundColor:
                              WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.indigoAccent;
                            }
                            return null;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _deleteCountController,
                  style: TextStyle(color: context.textColorPrimary),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _buildInputDecoration('删除字符个数', hint: '要删除的字符数量'),
                ),
              ],

              // 3. Range Custom Mode Inputs
              if (del.mode == DeleteMode.rangeCustom) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _deleteStartController,
                        style: TextStyle(color: context.textColorPrimary),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: _buildInputDecoration('起始索引 (0-based)'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text('至',
                          style: TextStyle(color: context.textColorSecondary)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _deleteEndController,
                        style: TextStyle(color: context.textColorPrimary),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: _buildInputDecoration('结束索引 (0-based)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '注意：区间为闭区间，如：1至3会删除第1, 2, 3个字符',
                  style: TextStyle(
                      color: context.textColorSecondary, fontSize: 12),
                ),
              ],

              // 4. Anchor Mode Inputs
              if (del.mode == DeleteMode.anchor) ...[
                TextField(
                  controller: _deleteAnchorController,
                  maxLength: 1,
                  style: TextStyle(color: context.textColorPrimary),
                  decoration: _buildInputDecoration('定位字符', hint: '输入单个字符'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('删除方向:',
                        style: TextStyle(color: context.textColorSecondary)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<DeleteDirection>(
                        segments: const [
                          ButtonSegment(
                              value: DeleteDirection.before,
                              label: Text('删除前侧')),
                          ButtonSegment(
                              value: DeleteDirection.after,
                              label: Text('删除后侧')),
                        ],
                        selected: {del.direction},
                        onSelectionChanged: (val) {
                          setState(() {
                            _rule = _rule.copyWith(
                                deleteRule: del.copyWith(direction: val.first));
                            _triggerChanged();
                          });
                        },
                        style: ButtonStyle(
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.indigo.withValues(alpha: 0.2);
                            }
                            return null;
                          }),
                          foregroundColor:
                              WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.indigoAccent;
                            }
                            return null;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: Text('删除定位字符本身',
                      style: TextStyle(color: context.textColorPrimary)),
                  value: del.includeAnchor,
                  activeColor: Colors.indigoAccent,
                  checkColor: Colors.white,
                  onChanged: (val) {
                    setState(() {
                      _rule = _rule.copyWith(
                          deleteRule:
                              del.copyWith(includeAnchor: val ?? false));
                      _triggerChanged();
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParentDirTab() {
    final pdir = _rule.parentDirRule;
    return Card(
      color: context.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          shrinkWrap: true,
          children: [
            _buildSwitchHeader('启用父目录名规则', pdir.enabled, (val) {
              setState(() {
                _rule =
                    _rule.copyWith(parentDirRule: pdir.copyWith(enabled: val));
                _triggerChanged();
              });
            }),
            const SizedBox(height: 8),
            if (pdir.enabled) ...[
              Text(
                '直接父文件夹名称将插入到新文件名中。',
                style:
                    TextStyle(color: context.textColorSecondary, fontSize: 13),
              ),
              const SizedBox(height: 10),
              _buildSeparatorSection(
                selectedType: _selectedParentDirSepType,
                customController: _parentDirSeparatorCustomController,
                onTypeChanged: (type) {
                  setState(() {
                    _selectedParentDirSepType = type;
                    final newSep = type == 'custom'
                        ? _parentDirSeparatorCustomController.text
                        : type;
                    _rule = _rule.copyWith(
                      parentDirRule:
                          _rule.parentDirRule.copyWith(separator: newSep),
                    );
                    _triggerChanged();
                  });
                },
              ),
              const SizedBox(height: 10),
              Text('插入位置:',
                  style: TextStyle(color: context.textColorSecondary)),
              const SizedBox(height: 6),
              SegmentedButton<InsertPosition>(
                segments: const [
                  ButtonSegment(value: InsertPosition.start, label: Text('开头')),
                  ButtonSegment(value: InsertPosition.end, label: Text('结尾')),
                  ButtonSegment(
                      value: InsertPosition.custom, label: Text('自定义')),
                ],
                selected: {pdir.position},
                onSelectionChanged: (val) {
                  setState(() {
                    _rule = _rule.copyWith(
                        parentDirRule: pdir.copyWith(position: val.first));
                    _triggerChanged();
                  });
                },
                style: ButtonStyle(
                  backgroundColor:
                      WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.indigo.withValues(alpha: 0.2);
                    }
                    return null;
                  }),
                  foregroundColor:
                      WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.indigoAccent;
                    }
                    return null;
                  }),
                ),
              ),
              if (pdir.position == InsertPosition.custom) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _parentDirIndexController,
                  style: TextStyle(color: context.textColorPrimary),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _buildInputDecoration('插入位置索引 (0-based)'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSeparatorSection({
    required String selectedType,
    required TextEditingController customController,
    required ValueChanged<String> onTypeChanged,
  }) {
    final Map<String, String> presets = {
      '': '无',
      '-': '-',
      '_': '_',
      ' ': '空格',
      '.': '.',
      'custom': '自定义',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('分隔符:',
            style: TextStyle(color: context.textColorSecondary, fontSize: 14)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: presets.entries.map((entry) {
            final isSelected = selectedType == entry.key;
            return ChoiceChip(
              label: Text(
                entry.value,
                style: TextStyle(
                  color: isSelected ? Colors.white : context.textColorSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  onTypeChanged(entry.key);
                }
              },
              selectedColor: Colors.indigo,
              backgroundColor: context.inputBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected
                      ? Colors.indigoAccent
                      : context.inputBorderColor,
                  width: 1,
                ),
              ),
              showCheckmark: false,
            );
          }).toList(),
        ),
        if (selectedType == 'custom') ...[
          const SizedBox(height: 12),
          SizedBox(
            width: 200,
            child: TextField(
              controller: customController,
              style: TextStyle(color: context.textColorPrimary),
              decoration: _buildInputDecoration(
                '自定义分隔符',
                hint: '例如: _v1_',
              ),
            ),
          ),
        ],
      ],
    );
  }
}
