import 'package:flutter/material.dart';
import '../utils/file_helper.dart';
import '../utils/theme_helper.dart';

class PreviewPanel extends StatefulWidget {
  final List<RenameItem> items;
  final bool isScanning;
  final VoidCallback onRenameStarted;
  final VoidCallback onRenameCompleted;
  final VoidCallback? onSearch;

  const PreviewPanel({
    super.key,
    required this.items,
    required this.isScanning,
    required this.onRenameStarted,
    required this.onRenameCompleted,
    this.onSearch,
  });

  @override
  State<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  bool _isExecuting = false;
  double _progress = 0.0;
  String _currentExecutingItem = '';
  int _successCount = 0;
  int _failCount = 0;

  int _sortColumnIndex = -1;
  bool _sortAscending = true;

  Widget _buildSortableHeader(String title, int columnIndex) {
    final isSelected = _sortColumnIndex == columnIndex;
    return InkWell(
      onTap: () {
        setState(() {
          if (_sortColumnIndex == columnIndex) {
            if (_sortAscending) {
              _sortAscending = false;
            } else {
              _sortColumnIndex = -1;
            }
          } else {
            _sortColumnIndex = columnIndex;
            _sortAscending = true;
          }
        });
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isSelected ? Colors.indigoAccent : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            isSelected
                ? (_sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down)
                : Icons.sort,
            size: 16,
            color: isSelected ? Colors.indigoAccent : Colors.grey[600],
          ),
        ],
      ),
    );
  }

  // Validation Cache: map of final path -> count of items proposing this path
  final Map<String, int> _pathCollisionMap = {};

  @override
  void didUpdateWidget(covariant PreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateItems();
  }

  void _validateItems() {
    _pathCollisionMap.clear();
    for (var item in widget.items) {
      if (item.newName.isEmpty) continue;
      final targetPath = item.newPath.toLowerCase();
      _pathCollisionMap[targetPath] = (_pathCollisionMap[targetPath] ?? 0) + 1;
    }
  }

  String? _getItemValidationError(RenameItem item) {
    if (item.newName.trim().isEmpty) {
      return '文件名不能为空';
    }
    
    // Check if newName matches oldName (no-op, not an error but worth knowing)
    if (item.newName == item.baseName) {
      return null;
    }

    final targetPath = item.newPath.toLowerCase();
    // Collision with other renaming items
    if ((_pathCollisionMap[targetPath] ?? 0) > 1) {
      return '命名冲突: 多个文件重命名为相同名字';
    }

    return null;
  }

  Future<void> _startRenameProcess() async {
    if (widget.items.isEmpty) return;

    // Filter out items that have no changes or are invalid
    final List<RenameItem> itemsToRename = widget.items.where((item) {
      final validation = _getItemValidationError(item);
      final hasChanges = item.newName != item.baseName;
      return hasChanges && validation == null;
    }).toList();

    if (itemsToRename.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有需要重命名的有效项目')),
      );
      return;
    }

    setState(() {
      _isExecuting = true;
      _progress = 0.0;
      _successCount = 0;
      _failCount = 0;
    });

    widget.onRenameStarted();

    await FileHelper.executeRename(
      itemsToRename,
      onItemComplete: (index, progress, item) {
        setState(() {
          _progress = progress;
          _currentExecutingItem = item.newName;
          if (item.isSuccess) {
            _successCount++;
          } else {
            _failCount++;
          }
        });
      },
      onAllComplete: () {
        setState(() {
          _isExecuting = false;
        });
        
        // Show outcome dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: context.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('重命名执行完毕', style: TextStyle(color: context.textColorPrimary, fontWeight: FontWeight.bold)),
            content: Text(
              '成功: $_successCount 个项目\n失败: $_failCount 个项目',
              style: TextStyle(color: context.textColorSecondary, fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onRenameCompleted();
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final changedCount = widget.items.where((item) => item.newName != item.baseName && _getItemValidationError(item) == null).length;

    List<RenameItem> sortedItems = List.from(widget.items);
    if (_sortColumnIndex == 0) {
      sortedItems.sort((a, b) {
        int cmp = a.currentName.toLowerCase().compareTo(b.currentName.toLowerCase());
        return _sortAscending ? cmp : -cmp;
      });
    } else if (_sortColumnIndex == 1) {
      sortedItems.sort((a, b) {
        final aDisplay = a.isDirectory ? a.newName : (a.newName + a.extension);
        final bDisplay = b.isDirectory ? b.newName : (b.newName + b.extension);
        int cmp = aDisplay.toLowerCase().compareTo(bDisplay.toLowerCase());
        return _sortAscending ? cmp : -cmp;
      });
    }

    return Card(
      color: context.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Preview & Execute Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '对比预览',
                        style: TextStyle(color: context.textColorPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '共 ${widget.items.length} 个项目，将更改 $changedCount 个',
                        style: TextStyle(color: context.textColorSecondary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: (widget.isScanning || _isExecuting || widget.onSearch == null)
                      ? null
                      : widget.onSearch,
                  icon: const Icon(Icons.search, size: 20),
                  label: const Text('预览'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigoAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: context.isDarkMode ? Colors.grey[800] : Colors.grey[300],
                    disabledForegroundColor: context.isDarkMode ? Colors.grey[600] : Colors.grey[500],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: (_isExecuting || widget.items.isEmpty || changedCount == 0)
                      ? null
                      : _startRenameProcess,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('一键应用'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigoAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: context.isDarkMode ? Colors.grey[800] : Colors.grey[300],
                    disabledForegroundColor: context.isDarkMode ? Colors.grey[600] : Colors.grey[500],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Execution Progress Overlay
            if (_isExecuting) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('正在重命名...', style: TextStyle(color: context.textColorPrimary, fontWeight: FontWeight.bold)),
                        Text('${(_progress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.indigoAccent)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: context.isDarkMode ? Colors.grey[800] : Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigoAccent),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '正在处理: $_currentExecutingItem',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.textColorSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Preview List Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.inputBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildSortableHeader('原名称', 0)),
                  Icon(Icons.arrow_forward, size: 16, color: context.textColorSecondary),
                  const SizedBox(width: 8),
                  Expanded(child: _buildSortableHeader('新名称', 1)),
                ],
              ),
            ),

            // Preview List
            Expanded(
              child: widget.isScanning
                  ? const Center(child: CircularProgressIndicator())
                  : widget.items.isEmpty
                      ? Center(
                          child: Text('暂无预览数据，请先选择文件夹并配置规则', style: TextStyle(color: context.textColorSecondary)),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: context.listBg,
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                          ),
                          child: ListView.separated(
                            itemCount: sortedItems.length,
                            separatorBuilder: (context, index) => Divider(color: context.borderColor, height: 1),
                            itemBuilder: (context, index) {
                              final item = sortedItems[index];
                              final validationError = _getItemValidationError(item);
                              final hasChanged = item.newName != item.baseName;
                              
                              final String displayOld = item.currentName;
                              final String displayNew = item.isDirectory 
                                  ? item.newName 
                                  : (item.newName + item.extension);

                              Color newNameColor = context.textColorSecondary;
                              Color rowBgColor = Colors.transparent;
                              Widget? trailingIcon;

                              if (validationError != null) {
                                newNameColor = context.isDarkMode ? Colors.redAccent : Colors.red[700]!;
                                rowBgColor = Colors.red.withOpacity(context.isDarkMode ? 0.05 : 0.08);
                                trailingIcon = Tooltip(
                                  message: validationError,
                                  child: Icon(Icons.error_outline, color: context.isDarkMode ? Colors.redAccent : Colors.red[700], size: 20),
                                );
                              } else if (hasChanged) {
                                newNameColor = context.isDarkMode ? Colors.greenAccent : Colors.green[700]!;
                                rowBgColor = Colors.green.withOpacity(context.isDarkMode ? 0.03 : 0.06);
                              }

                              return Container(
                                color: rowBgColor,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Tooltip(
                                              message: '点击打开: ${item.currentPath}',
                                              child: InkWell(
                                                onTap: () => FileHelper.openFileOrFolder(item.currentPath),
                                                child: Text(
                                                  displayOld,
                                                  style: TextStyle(
                                                    color: context.textColorPrimary,
                                                    fontSize: 13,
                                                    decoration: hasChanged ? TextDecoration.lineThrough : null,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Tooltip(
                                            message: '打开文件/文件夹',
                                            child: InkWell(
                                              onTap: () => FileHelper.openFileOrFolder(item.currentPath),
                                              borderRadius: BorderRadius.circular(4),
                                              child: Padding(
                                                padding: const EdgeInsets.all(4.0),
                                                child: Icon(Icons.open_in_new, size: 14, color: context.textColorSecondary),
                                              ),
                                            ),
                                          ),
                                          Tooltip(
                                            message: '在文件夹中定位',
                                            child: InkWell(
                                              onTap: () => FileHelper.locateInExplorer(item.currentPath),
                                              borderRadius: BorderRadius.circular(4),
                                              child: Padding(
                                                padding: const EdgeInsets.all(4.0),
                                                child: Icon(Icons.folder_open, size: 14, color: context.textColorSecondary),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right, size: 14, color: context.textColorSecondary),
                                    const SizedBox(width: 8),
                                    // New Name
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              displayNew,
                                              style: TextStyle(
                                                color: newNameColor,
                                                fontWeight: hasChanged ? FontWeight.bold : FontWeight.normal,
                                                fontSize: 13,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (trailingIcon != null) ...[
                                            const SizedBox(width: 4),
                                            trailingIcon,
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
