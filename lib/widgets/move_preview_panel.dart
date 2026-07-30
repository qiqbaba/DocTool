import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../utils/move_logic.dart';
import '../utils/file_helper.dart';
import '../utils/theme_helper.dart';

class MovePreviewPanel extends StatefulWidget {
  final List<MoveItem> items;
  final bool isScanning;
  final double scanProgress;
  final String scanStatus;
  final String sourceDirPath;
  final String targetDirPath;
  final MoveFilterRule rule;
  final ConflictStrategy conflictStrategy;
  final VoidCallback onMoveStarted;
  final VoidCallback onMoveCompleted;
  final VoidCallback? onSearch;
  final ValueChanged<String>? onItemSelectionChanged;

  const MovePreviewPanel({
    super.key,
    required this.items,
    required this.isScanning,
    this.scanProgress = 0.0,
    this.scanStatus = '',
    required this.sourceDirPath,
    required this.targetDirPath,
    required this.rule,
    required this.conflictStrategy,
    required this.onMoveStarted,
    required this.onMoveCompleted,
    this.onSearch,
    this.onItemSelectionChanged,
  });

  @override
  State<MovePreviewPanel> createState() => _MovePreviewPanelState();
}

class _MovePreviewPanelState extends State<MovePreviewPanel> {
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
              color: isSelected ? Colors.orangeAccent : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            isSelected
                ? (_sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down)
                : Icons.sort,
            size: 16,
            color: isSelected ? Colors.orangeAccent : Colors.grey[600],
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  int get _selectedCount =>
      widget.items.where((item) => item.isSelected).length;

  int get _selectedSizeSum {
    int sum = 0;
    for (var item in widget.items) {
      if (item.isSelected) {
        sum += item.size;
      }
    }
    return sum;
  }

  void _toggleSelectAll(bool? value) {
    for (var item in widget.items) {
      item.isSelected = value ?? false;
      widget.onItemSelectionChanged?.call(item.path);
    }
  }

  Future<void> _startMoveProcess() async {
    // 1. Verify target directory path
    if (widget.targetDirPath.isEmpty && !widget.rule.flattenToRoot) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先选择移动的目标文件夹！'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    // 2. Prevent moving source to a subfolder inside itself (infinite loops)
    final bool isLoopConflict = widget.rule.flattenToRoot
        ? p.isWithin(widget.sourceDirPath, widget.targetDirPath)
        : (p.isWithin(widget.sourceDirPath, widget.targetDirPath) ||
            p.equals(widget.sourceDirPath, widget.targetDirPath));

    if (isLoopConflict) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: context.cardBg,
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text('目录冲突'),
            ],
          ),
          content: Text(
            '目标文件夹不能是源文件夹的子文件夹，否则会导致文件循环搬移与结构损坏！请选择其他独立的目标路径。',
            style: TextStyle(color: context.textColorSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('好的',
                  style: TextStyle(color: Colors.orangeAccent)),
            ),
          ],
        ),
      );
      return;
    }

    final selectedItems =
        widget.items.where((item) => item.isSelected).toList();
    if (selectedItems.isEmpty) return;

    // Safety Dialogue Confirmation
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: context.cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: Colors.orangeAccent, size: 28),
              const SizedBox(width: 8),
              Text('确认批量移动？',
                  style: TextStyle(
                      color: context.textColorPrimary,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.rule.flattenToRoot
                    ? '您即将将子孙文件夹中的 ${selectedItems.length} 个文件拍平移动到根目录，并删除所有空子文件夹。\n总大小约为: ${_formatSize(_selectedSizeSum)}。'
                    : '您即将移动 ${selectedItems.length} 个项目。\n总大小约为: ${_formatSize(_selectedSizeSum)}。',
                style: TextStyle(color: context.textColorPrimary, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Text(
                '源目录:\n${widget.sourceDirPath}',
                style:
                    TextStyle(color: context.textColorSecondary, fontSize: 12),
              ),
              if (!widget.rule.flattenToRoot) ...[
                const SizedBox(height: 8),
                Text(
                  '目标目录:\n${widget.targetDirPath}',
                  style:
                      const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                widget.rule.flattenToRoot
                    ? '提示：移动完成后，所有空子文件夹将被自动递归清理。'
                    : '提示：跨分区移动大文件可能需要稍等片刻，此时会采用后台复制并删除源文件的Fallback方案。',
                style: TextStyle(
                    color: context.textColorSecondary,
                    fontSize: 12,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消',
                  style: TextStyle(color: context.textColorSecondary)),
            ),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('确认移动'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isExecuting = true;
      _progress = 0.0;
      _successCount = 0;
      _failCount = 0;
    });

    widget.onMoveStarted();

    int lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
    await MoveLogic.executeMove(
      widget.items,
      rootPath: widget.sourceDirPath,
      targetDirPath: widget.targetDirPath,
      rule: widget.rule,
      strategy: widget.conflictStrategy,
      onItemComplete: (index, progress, item) {
        if (item.isMoved) {
          _successCount++;
        } else {
          if (item.isSelected) {
            _failCount++;
          }
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        final isLast = index == widget.items.length - 1;
        if (isLast || now - lastUpdateMs >= 50) {
          lastUpdateMs = now;
          setState(() {
            _progress = progress;
            _currentExecutingItem = item.name;
          });
        }
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('移动完毕',
                style: TextStyle(
                    color: context.textColorPrimary,
                    fontWeight: FontWeight.bold)),
            content: Text(
              '移动成功: $_successCount 个项目\n移动失败: $_failCount 个项目\n共计处理空间: ${_formatSize(_selectedSizeSum)}',
              style: TextStyle(color: context.textColorSecondary, fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onMoveCompleted();
                },
                style:
                    TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
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
    final allChecked = widget.items.isNotEmpty &&
        widget.items.every((item) => item.isSelected);
    final someChecked =
        widget.items.any((item) => item.isSelected) && !allChecked;

    List<MoveItem> sortedItems = List.from(widget.items);
    if (_sortColumnIndex == 0) {
      sortedItems.sort((a, b) {
        int cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return _sortAscending ? cmp : -cmp;
      });
    } else if (_sortColumnIndex == 1) {
      sortedItems.sort((a, b) {
        int cmp =
            a.matchReason.toLowerCase().compareTo(b.matchReason.toLowerCase());
        return _sortAscending ? cmp : -cmp;
      });
    } else if (_sortColumnIndex == 2) {
      sortedItems.sort((a, b) {
        int cmp = a.size.compareTo(b.size);
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
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info & Action Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '扫描到 ${widget.items.length} 个项目，已选择 $_selectedCount 个，预计移动空间: ${_formatSize(_selectedSizeSum)}',
                        style: TextStyle(
                            color: context.textColorPrimary, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: (widget.isScanning ||
                          _isExecuting ||
                          widget.onSearch == null)
                      ? null
                      : widget.onSearch,
                  icon: const Icon(Icons.search, size: 20),
                  label: const Text('预览'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: context.isDarkMode
                        ? Colors.grey[800]
                        : Colors.grey[300],
                    disabledForegroundColor: context.isDarkMode
                        ? Colors.grey[600]
                        : Colors.grey[500],
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: (_isExecuting ||
                          widget.items.isEmpty ||
                          _selectedCount == 0)
                      ? null
                      : _startMoveProcess,
                  icon: const Icon(Icons.drive_file_move_outlined),
                  label: const Text('移动'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: context.isDarkMode
                        ? Colors.grey[800]
                        : Colors.grey[300],
                    disabledForegroundColor: context.isDarkMode
                        ? Colors.grey[600]
                        : Colors.grey[500],
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Progress Bar Overlay
            if (_isExecuting) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('正在移动文件...',
                            style: TextStyle(
                                color: context.textColorPrimary,
                                fontWeight: FontWeight.bold)),
                        Text('${(_progress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(color: Colors.orangeAccent)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: context.isDarkMode
                          ? Colors.grey[800]
                          : Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.orangeAccent),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '正在处理: $_currentExecutingItem',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.textColorSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Selection Header / Table Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.inputBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: allChecked ? true : (someChecked ? null : false),
                    tristate: true,
                    activeColor: Colors.orangeAccent,
                    onChanged: (val) {
                      if (val == true) {
                        _toggleSelectAll(true);
                      } else {
                        _toggleSelectAll(false);
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 5,
                    child: _buildSortableHeader('项目名称', 0),
                  ),
                  Expanded(
                    flex: 3,
                    child: _buildSortableHeader('匹配条件/类型', 1),
                  ),
                  Expanded(
                    flex: 2,
                    child: _buildSortableHeader('大小', 2),
                  ),
                ],
              ),
            ),

            Expanded(
              child: widget.isScanning
                  ? Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 400),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              height: 48,
                              width: 48,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.orangeAccent),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              widget.scanStatus.isNotEmpty
                                  ? widget.scanStatus
                                  : '正在扫描中...',
                              style: TextStyle(
                                  color: context.textColorPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: widget.scanProgress > 0.0
                                    ? widget.scanProgress
                                    : null,
                                backgroundColor: context.isDarkMode
                                    ? const Color(0xFF2D2D34)
                                    : Colors.grey[300],
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Colors.orangeAccent),
                                minHeight: 6,
                              ),
                            ),
                            if (widget.scanProgress > 0.0) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${(widget.scanProgress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : widget.items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_open,
                                size: 48,
                                color: context.textColorSecondary
                                    .withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.onSearch == null
                                    ? '尚未选择任何目标文件夹\n请点击左上角的“选择”按钮选择文件夹以开始'
                                    : '没有符合移动条件的文件/文件夹',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: context.textColorSecondary,
                                    fontSize: 14,
                                    height: 1.5),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: context.listBg,
                            borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(8)),
                          ),
                          child: ListView.separated(
                            itemCount: sortedItems.length,
                            separatorBuilder: (context, index) =>
                                Divider(color: context.borderColor, height: 1),
                            itemBuilder: (context, index) {
                              final item = sortedItems[index];

                              IconData iconData = Icons.insert_drive_file;
                              Color iconColor = Colors.grey;
                              if (item.isDirectory) {
                                iconData = Icons.folder;
                                iconColor = Colors.amber;
                              }

                              // Calculate planned move path description
                              String planDestPath = '';
                              final bool isAutoDelete = !item.isDirectory &&
                                  widget.rule.deleteSpecifiedSizeFiles &&
                                  item.size < widget.rule.deleteSizeLimitBytes;

                              if (isAutoDelete) {
                                planDestPath = '[自动删除]';
                              } else if (widget.rule.flattenToRoot) {
                                planDestPath =
                                    p.join(widget.sourceDirPath, item.name);
                              } else if (widget.targetDirPath.isNotEmpty) {
                                if (widget.rule.keepStructure) {
                                  final rel = p.relative(item.path,
                                      from: widget.sourceDirPath);
                                  planDestPath =
                                      p.join(widget.targetDirPath, rel);
                                } else {
                                  planDestPath =
                                      p.join(widget.targetDirPath, item.name);
                                }
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: item.isSelected,
                                      activeColor: Colors.orangeAccent,
                                      onChanged: (val) {
                                        item.isSelected = val ?? false;
                                        widget.onItemSelectionChanged
                                            ?.call(item.path);
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      flex: 5,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(iconData,
                                                  color: iconColor, size: 16),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Tooltip(
                                                  message: '点击打开: ${item.path}',
                                                  child: InkWell(
                                                    onTap: () => FileHelper
                                                        .openFileOrFolder(
                                                            item.path),
                                                    child: Text(
                                                      item.name,
                                                      style: TextStyle(
                                                        color: context
                                                            .textColorPrimary,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Tooltip(
                                            message: item.path,
                                            child: InkWell(
                                              onTap: () =>
                                                  FileHelper.openFileOrFolder(
                                                      item.path),
                                              child: Text(
                                                item.path,
                                                style: TextStyle(
                                                    color: context
                                                        .textColorSecondary,
                                                    fontSize: 11),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                          if (planDestPath.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Icon(
                                                  planDestPath == '[自动删除]'
                                                      ? Icons.delete_forever
                                                      : Icons
                                                          .subdirectory_arrow_right,
                                                  color:
                                                      planDestPath == '[自动删除]'
                                                          ? Colors.redAccent
                                                          : Colors.orangeAccent,
                                                  size: 11,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Tooltip(
                                                    message: planDestPath ==
                                                            '[自动删除]'
                                                        ? '此小文件将被自动删除'
                                                        : '移动至: $planDestPath',
                                                    child: Text(
                                                      planDestPath == '[自动删除]'
                                                          ? '将自动直接删除'
                                                          : '移动至: $planDestPath',
                                                      style: TextStyle(
                                                        color: planDestPath ==
                                                                '[自动删除]'
                                                            ? Colors.redAccent
                                                            : Colors
                                                                .orangeAccent,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            planDestPath ==
                                                                    '[自动删除]'
                                                                ? FontWeight
                                                                    .bold
                                                                : FontWeight
                                                                    .normal,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          if (item.error != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              '失败原因: ${item.error}',
                                              style: TextStyle(
                                                color: context.isDarkMode
                                                    ? Colors.redAccent
                                                    : Colors.red[700],
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orangeAccent
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: Colors.orangeAccent
                                                    .withValues(alpha: 0.2)),
                                          ),
                                          child: Text(
                                            item.matchReason,
                                            style: const TextStyle(
                                                color: Colors.orangeAccent,
                                                fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        item.isDirectory
                                            ? '-'
                                            : _formatSize(item.size),
                                        style: TextStyle(
                                            color: context.textColorPrimary,
                                            fontSize: 12),
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
