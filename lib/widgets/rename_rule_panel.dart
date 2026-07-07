import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/rename_logic.dart';

class RenameRulePanel extends StatefulWidget {
  final RenameRule initialRule;
  final bool initialIsFileTarget;
  final bool initialRecursive;
  final String initialExtensionFilter;
  final Function(
    RenameRule rule,
    bool isFileTarget,
    bool recursive,
    String extensionFilter,
  ) onChanged;

  const RenameRulePanel({
    super.key,
    required this.initialRule,
    required this.initialIsFileTarget,
    required this.initialRecursive,
    required this.initialExtensionFilter,
    required this.onChanged,
  });

  @override
  State<RenameRulePanel> createState() => _RenameRulePanelState();
}

class _RenameRulePanelState extends State<RenameRulePanel> with SingleTickerProviderStateMixin {
  late RenameRule _rule;
  late bool _isFileTarget;
  late bool _recursive;
  late String _extensionFilter;

  // Controllers
  final TextEditingController _extController = TextEditingController();
  final TextEditingController _insertTextController = TextEditingController();
  final TextEditingController _insertIndexController = TextEditingController();
  final TextEditingController _insertSeparatorCustomController = TextEditingController();
  final TextEditingController _deleteMatchController = TextEditingController();
  final TextEditingController _deleteCountController = TextEditingController();
  final TextEditingController _deleteStartController = TextEditingController();
  final TextEditingController _deleteEndController = TextEditingController();
  final TextEditingController _deleteAnchorController = TextEditingController();
  final TextEditingController _parentDirIndexController = TextEditingController();
  final TextEditingController _parentDirSeparatorCustomController = TextEditingController();

  late TabController _tabController;
  late String _selectedInsertSepType;
  late String _selectedParentDirSepType;

  @override
  void initState() {
    super.initState();
    _rule = widget.initialRule;
    _isFileTarget = widget.initialIsFileTarget;
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
          insertRule: _rule.insertRule.copyWith(separator: _insertSeparatorCustomController.text),
        );
        _triggerChanged();
      }
    });
    _deleteMatchController.addListener(() {
      _rule = _rule.copyWith(
        deleteRule: _rule.deleteRule.copyWith(matchText: _deleteMatchController.text),
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
        deleteRule: _rule.deleteRule.copyWith(anchorChar: _deleteAnchorController.text),
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
          parentDirRule: _rule.parentDirRule.copyWith(separator: _parentDirSeparatorCustomController.text),
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
    widget.onChanged(_rule, _isFileTarget, _recursive, _extensionFilter);
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
        borderSide: const BorderSide(color: Colors.indigo, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _buildSwitchHeader(String title, bool val, ValueChanged<bool> onToggle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Switch(
          value: val,
          onChanged: onToggle,
          activeColor: Colors.indigoAccent,
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
                  '重命名范围',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 12),
                
                // Object Type Segment
                Row(
                  children: [
                    const Text('对象类型:', style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('文件'),
                            icon: Icon(Icons.insert_drive_file),
                          ),
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('文件夹'),
                            icon: Icon(Icons.folder),
                          ),
                        ],
                        selected: {_isFileTarget},
                        onSelectionChanged: (newSelection) {
                          setState(() {
                            _isFileTarget = newSelection.first;
                            _triggerChanged();
                          });
                        },
                        style: const ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Recursive Switch
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isFileTarget ? '包含子孙文件 (递归)' : '包含子孙文件夹 (递归)',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    Switch(
                      value: _recursive,
                      onChanged: (val) {
                        setState(() {
                          _recursive = val;
                          _triggerChanged();
                        });
                      },
                      activeColor: Colors.indigoAccent,
                    ),
                  ],
                ),
                
                // Extension filter (Only for files)
                if (_isFileTarget) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _extController,
                    style: const TextStyle(color: Colors.white),
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
        
        const SizedBox(height: 16),
        
        // Tab header for Rules
        TabBar(
          controller: _tabController,
          labelColor: Colors.indigoAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigoAccent,
          tabs: const [
            Tab(text: '插入文本', icon: Icon(Icons.add_circle_outline)),
            Tab(text: '删除文本', icon: Icon(Icons.remove_circle_outline)),
            Tab(text: '插入父目录名', icon: Icon(Icons.folder_shared_outlined)),
          ],
        ),
        const SizedBox(height: 16),
        
        // Tab body for Rules
        SizedBox(
          height: 440,
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
      color: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          shrinkWrap: true,
          children: [
            _buildSwitchHeader('启用插入规则', ins.enabled, (val) {
              setState(() {
                _rule = _rule.copyWith(insertRule: ins.copyWith(enabled: val));
                _triggerChanged();
              });
            }),
            const SizedBox(height: 12),
            if (ins.enabled) ...[
              TextField(
                controller: _insertTextController,
                style: const TextStyle(color: Colors.white),
                decoration: _buildInputDecoration('插入内容', hint: '输入要插入的文本'),
              ),
              const SizedBox(height: 16),
              _buildSeparatorSection(
                selectedType: _selectedInsertSepType,
                customController: _insertSeparatorCustomController,
                onTypeChanged: (type) {
                  setState(() {
                    _selectedInsertSepType = type;
                    final newSep = type == 'custom' ? _insertSeparatorCustomController.text : type;
                    _rule = _rule.copyWith(
                      insertRule: _rule.insertRule.copyWith(separator: newSep),
                    );
                    _triggerChanged();
                  });
                },
              ),
              const SizedBox(height: 16),
              const Text('插入位置:', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              SegmentedButton<InsertPosition>(
                segments: const [
                  ButtonSegment(value: InsertPosition.start, label: Text('开头')),
                  ButtonSegment(value: InsertPosition.end, label: Text('结尾')),
                  ButtonSegment(value: InsertPosition.custom, label: Text('自定义')),
                ],
                selected: {ins.position},
                onSelectionChanged: (val) {
                  setState(() {
                    _rule = _rule.copyWith(insertRule: ins.copyWith(position: val.first));
                    _triggerChanged();
                  });
                },
              ),
              if (ins.position == InsertPosition.custom) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _insertIndexController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _buildInputDecoration('插入位置索引 (0-based)', hint: '例如: 3 表示在第3个字符处插入'),
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
      color: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          shrinkWrap: true,
          children: [
            _buildSwitchHeader('启用删除规则', del.enabled, (val) {
              setState(() {
                _rule = _rule.copyWith(deleteRule: del.copyWith(enabled: val));
                _triggerChanged();
              });
            }),
            const SizedBox(height: 12),
            if (del.enabled) ...[
              const Text('删除模式:', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              DropdownButtonFormField<DeleteMode>(
                value: del.mode,
                dropdownColor: const Color(0xFF1E1E22),
                style: const TextStyle(color: Colors.white),
                decoration: _buildInputDecoration('选择删除模式'),
                items: const [
                  DropdownMenuItem(value: DeleteMode.match, child: Text('匹配内容删除')),
                  DropdownMenuItem(value: DeleteMode.rangeEnds, child: Text('开头/结尾字符删除')),
                  DropdownMenuItem(value: DeleteMode.rangeCustom, child: Text('自定义区间删除')),
                  DropdownMenuItem(value: DeleteMode.anchor, child: Text('定位字符前后删除')),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    setState(() {
                      _rule = _rule.copyWith(deleteRule: del.copyWith(mode: mode));
                      _triggerChanged();
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              
              // 1. Match Mode Inputs
              if (del.mode == DeleteMode.match) ...[
                TextField(
                  controller: _deleteMatchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _buildInputDecoration('要删除的内容', hint: '输入被匹配的关键字'),
                ),
              ],
              
              // 2. Range Ends Mode Inputs
              if (del.mode == DeleteMode.rangeEnds) ...[
                Row(
                  children: [
                    const Text('方向:', style: TextStyle(color: Colors.grey)),
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
                            _rule = _rule.copyWith(deleteRule: del.copyWith(fromStart: val.first));
                            _triggerChanged();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _deleteCountController,
                  style: const TextStyle(color: Colors.white),
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
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _buildInputDecoration('起始索引 (0-based)'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text('至', style: TextStyle(color: Colors.grey)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _deleteEndController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _buildInputDecoration('结束索引 (0-based)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '注意：区间为闭区间，如：1至3会删除第1, 2, 3个字符',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
              
              // 4. Anchor Mode Inputs
              if (del.mode == DeleteMode.anchor) ...[
                TextField(
                  controller: _deleteAnchorController,
                  maxLength: 1,
                  style: const TextStyle(color: Colors.white),
                  decoration: _buildInputDecoration('定位字符', hint: '输入单个字符'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('删除方向:', style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<DeleteDirection>(
                        segments: const [
                          ButtonSegment(value: DeleteDirection.before, label: Text('删除前侧')),
                          ButtonSegment(value: DeleteDirection.after, label: Text('删除后侧')),
                        ],
                        selected: {del.direction},
                        onSelectionChanged: (val) {
                          setState(() {
                            _rule = _rule.copyWith(deleteRule: del.copyWith(direction: val.first));
                            _triggerChanged();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('删除定位字符本身', style: TextStyle(color: Colors.white)),
                  value: del.includeAnchor,
                  activeColor: Colors.indigoAccent,
                  checkColor: Colors.white,
                  onChanged: (val) {
                    setState(() {
                      _rule = _rule.copyWith(deleteRule: del.copyWith(includeAnchor: val ?? false));
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
      color: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          shrinkWrap: true,
          children: [
            _buildSwitchHeader('启用父目录名规则', pdir.enabled, (val) {
              setState(() {
                _rule = _rule.copyWith(parentDirRule: pdir.copyWith(enabled: val));
                _triggerChanged();
              });
            }),
            const SizedBox(height: 12),
            if (pdir.enabled) ...[
              const Text(
                '直接父文件夹名称将插入到新文件名中。',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _buildSeparatorSection(
                selectedType: _selectedParentDirSepType,
                customController: _parentDirSeparatorCustomController,
                onTypeChanged: (type) {
                  setState(() {
                    _selectedParentDirSepType = type;
                    final newSep = type == 'custom' ? _parentDirSeparatorCustomController.text : type;
                    _rule = _rule.copyWith(
                      parentDirRule: _rule.parentDirRule.copyWith(separator: newSep),
                    );
                    _triggerChanged();
                  });
                },
              ),
              const SizedBox(height: 16),
              const Text('插入位置:', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              SegmentedButton<InsertPosition>(
                segments: const [
                  ButtonSegment(value: InsertPosition.start, label: Text('开头')),
                  ButtonSegment(value: InsertPosition.end, label: Text('结尾')),
                  ButtonSegment(value: InsertPosition.custom, label: Text('自定义')),
                ],
                selected: {pdir.position},
                onSelectionChanged: (val) {
                  setState(() {
                    _rule = _rule.copyWith(parentDirRule: pdir.copyWith(position: val.first));
                    _triggerChanged();
                  });
                },
              ),
              if (pdir.position == InsertPosition.custom) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _parentDirIndexController,
                  style: const TextStyle(color: Colors.white),
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
        const Text('分隔符:', style: TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: presets.entries.map((entry) {
            final isSelected = selectedType == entry.key;
            return ChoiceChip(
              label: Text(
                entry.value,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[300],
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
              backgroundColor: const Color(0xFF1E1E22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected ? Colors.indigoAccent : const Color(0xFF2C2C35),
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
              style: const TextStyle(color: Colors.white),
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
