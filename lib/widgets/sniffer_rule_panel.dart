import 'package:flutter/material.dart';
import '../utils/sniffer_logic.dart';
import '../utils/theme_helper.dart';

class SnifferRulePanel extends StatefulWidget {
  final SnifferRule initialRule;
  final Function(SnifferRule rule) onChanged;

  const SnifferRulePanel({
    super.key,
    required this.initialRule,
    required this.onChanged,
  });

  @override
  State<SnifferRulePanel> createState() => _SnifferRulePanelState();
}

class _SnifferRulePanelState extends State<SnifferRulePanel> {
  late SnifferRule _rule;

  // Controllers for Custom Inputs
  final TextEditingController _wrapperStartController = TextEditingController();
  final TextEditingController _wrapperEndController = TextEditingController();
  final TextEditingController _separatorCustomController =
      TextEditingController();

  late String
      _selectedWrapperType; // 'bracket', 'parenthesis', 'brace', 'custom'
  late String
      _selectedSeparatorType; // 'comma', 'space', 'underscore', 'dash', 'custom'

  @override
  void initState() {
    super.initState();
    _rule = widget.initialRule;

    // Determine wrapper presets
    if (_rule.wrapperStart == ' [' && _rule.wrapperEnd == ']') {
      _selectedWrapperType = 'bracket';
    } else if (_rule.wrapperStart == ' (' && _rule.wrapperEnd == ')') {
      _selectedWrapperType = 'parenthesis';
    } else if (_rule.wrapperStart == ' {' && _rule.wrapperEnd == '}') {
      _selectedWrapperType = 'brace';
    } else {
      _selectedWrapperType = 'custom';
      _wrapperStartController.text = _rule.wrapperStart;
      _wrapperEndController.text = _rule.wrapperEnd;
    }

    // Determine separator presets
    if (_rule.separator == '') {
      _selectedSeparatorType = 'none';
    } else if (_rule.separator == ', ') {
      _selectedSeparatorType = 'comma';
    } else if (_rule.separator == ' ') {
      _selectedSeparatorType = 'space';
    } else if (_rule.separator == '_') {
      _selectedSeparatorType = 'underscore';
    } else if (_rule.separator == '-') {
      _selectedSeparatorType = 'dash';
    } else {
      _selectedSeparatorType = 'custom';
      _separatorCustomController.text = _rule.separator;
    }

    // Setup custom input listeners
    _wrapperStartController.addListener(_onCustomWrapperChanged);
    _wrapperEndController.addListener(_onCustomWrapperChanged);
    _separatorCustomController.addListener(_onCustomSeparatorChanged);
  }

  @override
  void dispose() {
    _wrapperStartController.dispose();
    _wrapperEndController.dispose();
    _separatorCustomController.dispose();
    super.dispose();
  }

  void _onCustomWrapperChanged() {
    if (_selectedWrapperType == 'custom') {
      setState(() {
        _rule = _rule.copyWith(
          wrapperStart: _wrapperStartController.text,
          wrapperEnd: _wrapperEndController.text,
        );
      });
      widget.onChanged(_rule);
    }
  }

  void _onCustomSeparatorChanged() {
    if (_selectedSeparatorType == 'custom') {
      setState(() {
        _rule = _rule.copyWith(
          separator: _separatorCustomController.text,
        );
      });
      widget.onChanged(_rule);
    }
  }

  void _triggerChanged(SnifferRule newRule) {
    setState(() {
      _rule = newRule;
    });
    widget.onChanged(_rule);
  }

  // Get color representing each file category (same palette as progress bar)
  Color _getCategoryColor(String category) {
    switch (category) {
      case FileCategory.video:
        return Colors.purpleAccent;
      case FileCategory.image:
        return Colors.blueAccent;
      case FileCategory.archive:
        return Colors.orangeAccent;
      case FileCategory.document:
        return Colors.greenAccent;
      case FileCategory.audio:
        return Colors.pinkAccent;
      default:
        return Colors.grey;
    }
  }

  // Icon for category
  IconData _getCategoryIcon(String category) {
    switch (category) {
      case FileCategory.video:
        return Icons.movie;
      case FileCategory.image:
        return Icons.image;
      case FileCategory.archive:
        return Icons.archive;
      case FileCategory.document:
        return Icons.description;
      case FileCategory.audio:
        return Icons.audiotrack;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
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
            // Rule Title
            Row(
              children: [
                const Icon(Icons.tune, color: Colors.purpleAccent),
                const SizedBox(width: 8),
                Text(
                  '统计规则配置',
                  style: TextStyle(
                    color: context.textColorPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Section 1: Scan Options
            _buildSectionHeader('扫描范围配置'),
            const SizedBox(height: 6),
            SwitchListTile(
              title: Text('包含深层子文件夹的文件',
                  style:
                      TextStyle(color: context.textColorPrimary, fontSize: 14)),
              subtitle: Text('开启则统计子目录下所有深度的文件；关闭则仅统计该子目录下直属的文件。',
                  style: TextStyle(
                      color: context.textColorSecondary, fontSize: 12)),
              value: _rule.recursive,
              activeColor: Colors.purpleAccent,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) {
                _triggerChanged(_rule.copyWith(recursive: val));
              },
            ),
            const Divider(height: 24),

            // Section 2: Enabled Categories (Grid/Chips)
            _buildSectionHeader('统计文件类型 (支持选择性排除)'),
            const SizedBox(height: 10),
            // 全选/取消全选
            Row(
              children: [
                _buildSelectAllButton(),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: FileCategory.all
                  .where((cat) => cat != FileCategory.other)
                  .map((cat) {
                final isEnabled = _rule.enabledTypes.contains(cat);
                final color = _getCategoryColor(cat);
                return FilterChip(
                  avatar: Icon(
                    _getCategoryIcon(cat),
                    size: 16,
                    color:
                        isEnabled ? Colors.white : context.textColorSecondary,
                  ),
                  label: Text(cat),
                  selected: isEnabled,
                  checkmarkColor: Colors.white,
                  selectedColor: color.withOpacity(0.85),
                  backgroundColor: context.inputBg,
                  labelStyle: TextStyle(
                    color: isEnabled ? Colors.white : context.textColorPrimary,
                    fontSize: 13,
                    fontWeight: isEnabled ? FontWeight.bold : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isEnabled ? color : context.inputBorderColor,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onSelected: (bool selected) {
                    final newTypes = Set<String>.from(_rule.enabledTypes);
                    if (selected) {
                      newTypes.add(cat);
                    } else {
                      newTypes.remove(cat);
                    }
                    _triggerChanged(_rule.copyWith(enabledTypes: newTypes));
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: Text('统计"其他"类别',
                  style:
                      TextStyle(color: context.textColorPrimary, fontSize: 13)),
              subtitle: Text('若目标文件夹中包含未选中的文件类型，统计为"其他"',
                  style: TextStyle(
                      color: context.textColorSecondary, fontSize: 11)),
              value: _rule.enableOther,
              activeColor: Colors.purpleAccent,
              contentPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (val) {
                _triggerChanged(_rule.copyWith(enableOther: val ?? true));
              },
            ),
            const Divider(height: 24),

            // Section 3: Append Format Options
            _buildSectionHeader('命名追加格式设置'),
            const SizedBox(height: 12),

            // Show Size & Show Count Switches
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    title: Text('包含文件大小',
                        style: TextStyle(
                            color: context.textColorPrimary, fontSize: 13)),
                    subtitle: Text('如: 1.2GB',
                        style: TextStyle(
                            color: context.textColorSecondary, fontSize: 11)),
                    value: _rule.showSize,
                    activeColor: Colors.purpleAccent,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (val) {
                      _triggerChanged(_rule.copyWith(showSize: val ?? false));
                    },
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    title: Text('包含文件数量',
                        style: TextStyle(
                            color: context.textColorPrimary, fontSize: 13)),
                    subtitle: Text('如: 5个',
                        style: TextStyle(
                            color: context.textColorSecondary, fontSize: 11)),
                    value: _rule.showCount,
                    activeColor: Colors.purpleAccent,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (val) {
                      _triggerChanged(_rule.copyWith(showCount: val ?? false));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            CheckboxListTile(
              title: Text('隐藏统计结果为 0 的类型',
                  style:
                      TextStyle(color: context.textColorPrimary, fontSize: 13)),
              value: _rule.hideZero,
              activeColor: Colors.purpleAccent,
              contentPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (val) {
                _triggerChanged(_rule.copyWith(hideZero: val ?? false));
              },
            ),
            CheckboxListTile(
              title: Text('空文件夹不追加统计后缀',
                  style:
                      TextStyle(color: context.textColorPrimary, fontSize: 13)),
              value: _rule.skipEmptyFolder,
              activeColor: Colors.purpleAccent,
              contentPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (val) {
                _triggerChanged(_rule.copyWith(skipEmptyFolder: val ?? false));
              },
            ),
            const SizedBox(height: 10),

            // Wrapper characters
            Text('包裹符号',
                style: TextStyle(
                    color: context.textColorSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: {
                'bracket': '[ ]',
                'parenthesis': '( )',
                'brace': '{ }',
                'custom': '自定义',
              }.entries.map((entry) {
                final isSelected = _selectedWrapperType == entry.key;
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
                      setState(() {
                        _selectedWrapperType = entry.key;
                      });
                      if (entry.key == 'bracket') {
                        _triggerChanged(
                            _rule.copyWith(wrapperStart: ' [', wrapperEnd: ']'));
                      } else if (entry.key == 'parenthesis') {
                        _triggerChanged(
                            _rule.copyWith(wrapperStart: ' (', wrapperEnd: ')'));
                      } else if (entry.key == 'brace') {
                        _triggerChanged(
                            _rule.copyWith(wrapperStart: ' {', wrapperEnd: '}'));
                      } else {
                        _triggerChanged(
                            _rule.copyWith(
                              wrapperStart: _wrapperStartController.text,
                              wrapperEnd: _wrapperEndController.text,
                            ));
                      }
                    }
                  },
                  selectedColor: Colors.purple,
                  backgroundColor: context.inputBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isSelected
                          ? Colors.purpleAccent
                          : context.inputBorderColor,
                      width: 1,
                    ),
                  ),
                  showCheckmark: false,
                );
              }).toList(),
            ),
            if (_selectedWrapperType == 'custom') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _wrapperStartController,
                      style: TextStyle(
                          color: context.textColorPrimary, fontSize: 13),
                      decoration:
                          _buildInputDecoration('左包裹符 (前缀)', hint: '例如： ['),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _wrapperEndController,
                      style: TextStyle(
                          color: context.textColorPrimary, fontSize: 13),
                      decoration:
                          _buildInputDecoration('右包裹符 (后缀)', hint: '例如： ]'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),

            // Separator settings
            Text('连接分隔符',
                style: TextStyle(
                    color: context.textColorSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: {
                'none': '无',
                'comma': ', ',
                'space': '空格',
                'underscore': '_',
                'dash': '-',
                'custom': '自定义',
              }.entries.map((entry) {
                final isSelected = _selectedSeparatorType == entry.key;
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
                      setState(() {
                        _selectedSeparatorType = entry.key;
                      });
                      if (entry.key == 'none') {
                        _triggerChanged(_rule.copyWith(separator: ''));
                      } else if (entry.key == 'comma') {
                        _triggerChanged(_rule.copyWith(separator: ', '));
                      } else if (entry.key == 'space') {
                        _triggerChanged(_rule.copyWith(separator: ' '));
                      } else if (entry.key == 'underscore') {
                        _triggerChanged(_rule.copyWith(separator: '_'));
                      } else if (entry.key == 'dash') {
                        _triggerChanged(_rule.copyWith(separator: '-'));
                      } else {
                        _triggerChanged(
                            _rule.copyWith(separator: _separatorCustomController.text));
                      }
                    }
                  },
                  selectedColor: Colors.purple,
                  backgroundColor: context.inputBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isSelected
                          ? Colors.purpleAccent
                          : context.inputBorderColor,
                      width: 1,
                    ),
                  ),
                  showCheckmark: false,
                );
              }).toList(),
            ),
            if (_selectedSeparatorType == 'custom') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _separatorCustomController,
                style: TextStyle(color: context.textColorPrimary, fontSize: 13),
                decoration:
                    _buildInputDecoration('连接符内容', hint: '请输入分类之间的连接字符'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建全选/取消全选按钮
  Widget _buildSelectAllButton() {
    final allCategories =
        FileCategory.all.where((cat) => cat != FileCategory.other).toList();
    final allEnabled =
        allCategories.every((cat) => _rule.enabledTypes.contains(cat));
    final noneEnabled =
        allCategories.every((cat) => !_rule.enabledTypes.contains(cat));

    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            final newTypes = Set<String>.from(allCategories);
            _triggerChanged(_rule.copyWith(enabledTypes: newTypes));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: allEnabled
                  ? Colors.purpleAccent.withOpacity(0.2)
                  : context.inputBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    allEnabled ? Colors.purpleAccent : context.inputBorderColor,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.select_all,
                  size: 14,
                  color: allEnabled
                      ? Colors.purpleAccent
                      : context.textColorSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '全选',
                  style: TextStyle(
                    color: allEnabled
                        ? Colors.purpleAccent
                        : context.textColorSecondary,
                    fontSize: 12,
                    fontWeight:
                        allEnabled ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            _triggerChanged(_rule.copyWith(enabledTypes: <String>{}));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: noneEnabled
                  ? Colors.redAccent.withOpacity(0.15)
                  : context.inputBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    noneEnabled ? Colors.redAccent : context.inputBorderColor,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.deselect,
                  size: 14,
                  color: noneEnabled
                      ? Colors.redAccent
                      : context.textColorSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '取消全选',
                  style: TextStyle(
                    color: noneEnabled
                        ? Colors.redAccent
                        : context.textColorSecondary,
                    fontSize: 12,
                    fontWeight:
                        noneEnabled ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: context.textColorPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: context.textColorSecondary, fontSize: 12),
      hintStyle: TextStyle(
          color: context.textColorSecondary.withOpacity(0.6), fontSize: 12),
      filled: true,
      fillColor: context.inputBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.inputBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.purpleAccent),
      ),
    );
  }
}
