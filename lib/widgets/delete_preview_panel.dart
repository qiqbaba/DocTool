import 'package:flutter/material.dart';
import '../utils/delete_logic.dart';
import '../utils/file_helper.dart';
import '../utils/theme_helper.dart';

class DeletePreviewPanel extends StatefulWidget {
  final List<DeleteItem> items;
  final bool isScanning;
  final double scanProgress;
  final String scanStatus;
  final VoidCallback onDeleteStarted;
  final VoidCallback onDeleteCompleted;
  final VoidCallback? onSearch;

  const DeletePreviewPanel({
    super.key,
    required this.items,
    required this.isScanning,
    this.scanProgress = 0.0,
    this.scanStatus = '',
    required this.onDeleteStarted,
    required this.onDeleteCompleted,
    this.onSearch,
  });

  @override
  State<DeletePreviewPanel> createState() => _DeletePreviewPanelState();
}

class _DeletePreviewPanelState extends State<DeletePreviewPanel> {
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
              color: isSelected ? Colors.redAccent : Colors.grey,
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
            color: isSelected ? Colors.redAccent : Colors.grey[600],
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

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
    setState(() {
      for (var item in widget.items) {
        item.isSelected = value ?? false;
      }
    });
  }

  Future<void> _startDeleteProcess() async {
    final selectedItems =
        widget.items.where((item) => item.isSelected).toList();
    if (selectedItems.isEmpty) return;

    // Safety Dialogue with Checkbox Confirmation
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool understood = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cardBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.redAccent, size: 28),
                  const SizedBox(width: 8),
                  Text('确认批量删除？',
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
                    '您即将删除 ${selectedItems.length} 个文件或文件夹。\n预计释放空间: ${_formatSize(_selectedSizeSum)}。',
                    style: TextStyle(
                        color: context.textColorPrimary, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '警告：本次删除将直接从磁盘中永久删除（硬删除），不经过系统回收站，数据一经删除将无法找回！',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: Text(
                      '我已理解该操作的严重性，并确认删除上述选定文件。',
                      style: TextStyle(
                          color: context.textColorSecondary, fontSize: 12),
                    ),
                    value: understood,
                    activeColor: Colors.redAccent,
                    onChanged: (val) {
                      setDialogState(() {
                        understood = val ?? false;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
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
                  onPressed:
                      understood ? () => Navigator.pop(context, true) : null,
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('确认永久删除'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: context.isDarkMode
                        ? Colors.grey[800]
                        : Colors.grey[300],
                    disabledForegroundColor: context.isDarkMode
                        ? Colors.grey[600]
                        : Colors.grey[500],
                  ),
                ),
              ],
            );
          },
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

    widget.onDeleteStarted();

    await DeleteLogic.executeDelete(
      widget.items,
      onItemComplete: (index, progress, item) {
        setState(() {
          _progress = progress;
          _currentExecutingItem = item.name;
          if (item.isDeleted) {
            _successCount++;
          } else {
            // Note: If duplicate or skipped (unselected), it shouldn't count as failure
            if (item.isSelected) {
              _failCount++;
            }
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('清理完毕',
                style: TextStyle(
                    color: context.textColorPrimary,
                    fontWeight: FontWeight.bold)),
            content: Text(
              '删除成功: $_successCount 个项目\n删除失败: $_failCount 个项目\n共释放空间: ${_formatSize(_selectedSizeSum)}',
              style: TextStyle(color: context.textColorSecondary, fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onDeleteCompleted();
                },
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
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

    List<DeleteItem> sortedItems = List.from(widget.items);
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
        padding: const EdgeInsets.all(16.0),
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
                        '清理队列预览',
                        style: TextStyle(
                            color: context.textColorPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '扫描到 ${widget.items.length} 个项目，已选择 $_selectedCount 个，预计释放空间: ${_formatSize(_selectedSizeSum)}',
                        style: TextStyle(
                            color: context.textColorSecondary, fontSize: 12),
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
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
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
                      : _startDeleteProcess,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('删除'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
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
            const SizedBox(height: 16),

            // Progress Bar Overlay
            if (_isExecuting) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('正在删除文件...',
                            style: TextStyle(
                                color: context.textColorPrimary,
                                fontWeight: FontWeight.bold)),
                        Text('${(_progress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(color: Colors.redAccent)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: context.isDarkMode
                          ? Colors.grey[800]
                          : Colors.grey[300],
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '正在删除: $_currentExecutingItem',
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

            // Selection Header Table Header
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
                    activeColor: Colors.redAccent,
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
                    child: _buildSortableHeader('匹配原因', 1),
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
                              color: Colors.black.withOpacity(0.15),
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
                                    Colors.redAccent),
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
                                    Colors.redAccent),
                                minHeight: 6,
                              ),
                            ),
                            if (widget.scanProgress > 0.0) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${(widget.scanProgress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                    color: Colors.redAccent,
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
                                color:
                                    context.textColorSecondary.withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.onSearch == null
                                    ? '尚未选择任何目标文件夹\n请点击左上角的“选择”按钮选择文件夹以开始'
                                    : '没有符合删除条件的文件/文件夹',
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

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                child: Row(
                                  children: [
                                    // Checkbox for item
                                    Checkbox(
                                      value: item.isSelected,
                                      activeColor: Colors.redAccent,
                                      onChanged: (val) {
                                        setState(() {
                                          item.isSelected = val ?? false;
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 4),

                                    // Icon and file info
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
                                                      style: const TextStyle(
                                                        color: Colors.white,
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
                                        ],
                                      ),
                                    ),

                                    // Match Reason Label
                                    Expanded(
                                      flex: 3,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: Colors.redAccent
                                                    .withOpacity(0.2)),
                                          ),
                                          child: Text(
                                            item.matchReason,
                                            style: const TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Size Column
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _formatSize(item.size),
                                            style: TextStyle(
                                                color: context.textColorPrimary,
                                                fontSize: 12),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatDate(item.lastModified),
                                            style: TextStyle(
                                                color:
                                                    context.textColorSecondary,
                                                fontSize: 10),
                                          ),
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
