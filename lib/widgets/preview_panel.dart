import 'package:flutter/material.dart';
import '../utils/file_helper.dart';

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
            backgroundColor: const Color(0xFF1E1E22),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('重命名执行完毕', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Text(
              '成功: $_successCount 个项目\n失败: $_failCount 个项目',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
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

    return Card(
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
            // Header: Preview & Execute Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '对比预览',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '共 ${widget.items.length} 个项目，将更改 $changedCount 个',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                    disabledBackgroundColor: Colors.grey[800],
                    disabledForegroundColor: Colors.grey[600],
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
                    disabledBackgroundColor: Colors.grey[800],
                    disabledForegroundColor: Colors.grey[600],
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
                        const Text('正在重命名...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('${(_progress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.indigoAccent)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: Colors.grey[800],
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigoAccent),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '正在处理: $_currentExecutingItem',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Preview List Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E22),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: const Row(
                children: [
                  Expanded(child: Text('原名称', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                  Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                  SizedBox(width: 8),
                  Expanded(child: Text('新名称', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                ],
              ),
            ),

            // Preview List
            Expanded(
              child: widget.isScanning
                  ? const Center(child: CircularProgressIndicator())
                  : widget.items.isEmpty
                      ? const Center(
                          child: Text('暂无预览数据，请先选择文件夹并配置规则', style: TextStyle(color: Colors.grey)),
                        )
                      : Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF1A1A1E),
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                          ),
                          child: ListView.separated(
                            itemCount: widget.items.length,
                            separatorBuilder: (context, index) => const Divider(color: Color(0xFF232329), height: 1),
                            itemBuilder: (context, index) {
                              final item = widget.items[index];
                              final validationError = _getItemValidationError(item);
                              final hasChanged = item.newName != item.baseName;
                              
                              final String displayOld = item.currentName;
                              final String displayNew = item.isDirectory 
                                  ? item.newName 
                                  : (item.newName + item.extension);

                              Color newNameColor = Colors.grey[400]!;
                              Color rowBgColor = Colors.transparent;
                              Widget? trailingIcon;

                              if (validationError != null) {
                                newNameColor = Colors.redAccent;
                                rowBgColor = Colors.red.withOpacity(0.05);
                                trailingIcon = Tooltip(
                                  message: validationError,
                                  child: const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                                );
                              } else if (hasChanged) {
                                newNameColor = Colors.greenAccent;
                                rowBgColor = Colors.green.withOpacity(0.03);
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
                                                    color: Colors.grey[300],
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
                                                child: Icon(Icons.open_in_new, size: 14, color: Colors.grey[500]),
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
                                                child: Icon(Icons.folder_open, size: 14, color: Colors.grey[500]),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
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
