import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import '../utils/sniffer_logic.dart';
import '../utils/theme_helper.dart';

class SnifferPreviewPanel extends StatefulWidget {
  final List<SnifferFolderItem> items;
  final bool isScanning;
  final double scanProgress;
  final String scanStatus;
  final VoidCallback onRenameCompleted;
  final VoidCallback? onSearch;
  final VoidCallback? onSelectDirectory;
  final SnifferRule rule;
  final ValueChanged<String>? onItemSelectionChanged;

  const SnifferPreviewPanel({
    super.key,
    required this.items,
    required this.isScanning,
    this.scanProgress = 0.0,
    this.scanStatus = '',
    required this.onRenameCompleted,
    required this.rule,
    this.onSearch,
    this.onSelectDirectory,
    this.onItemSelectionChanged,
  });

  @override
  State<SnifferPreviewPanel> createState() => _SnifferPreviewPanelState();
}

class _SnifferPreviewPanelState extends State<SnifferPreviewPanel> {
  bool _isExecuting = false;
  double _progress = 0.0;
  String _currentExecutingItem = '';
  int _successCount = 0;
  int _failCount = 0;

  int _sortColumnIndex = -1;
  bool _sortAscending = true;

  // 展开列表项的集合
  final Set<String> _expandedPaths = {};

  // Collision map to detect name conflict
  final Map<String, int> _pathCollisionMap = {};

  final GlobalKey<PopupMenuButtonState<String>> _moreMenuKey =
      GlobalKey<PopupMenuButtonState<String>>();

  @override
  void didUpdateWidget(covariant SnifferPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _validateCollisions();
    }
  }

  void _validateCollisions() {
    _pathCollisionMap.clear();
    for (var item in widget.items) {
      if (!item.isSelected) continue;
      if (item.newName.isEmpty) continue;
      final targetPath = item.newPath.toLowerCase();
      _pathCollisionMap[targetPath] = (_pathCollisionMap[targetPath] ?? 0) + 1;
    }
  }

  String? _getItemValidationError(SnifferFolderItem item) {
    if (item.newName.trim().isEmpty) {
      return '文件夹名不能为空';
    }

    if (item.newName == item.currentName) {
      return null;
    }

    final targetPath = item.newPath.toLowerCase();
    if ((_pathCollisionMap[targetPath] ?? 0) > 1) {
      return '命名冲突: 多个文件夹目标名称相同';
    }

    return null;
  }

  // Execute Rename to append statistics
  Future<void> _startRename() async {
    final list = widget.items.where((item) {
      final validation = _getItemValidationError(item);
      final hasChanges = item.newName != item.currentName;
      return item.isSelected && hasChanges && validation == null;
    }).toList();

    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可执行重命名的有效文件夹')),
      );
      return;
    }

    setState(() {
      _isExecuting = true;
      _progress = 0.0;
      _successCount = 0;
      _failCount = 0;
    });

    await SnifferLogic.executeSnifferRename(
      list,
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
        _showResultDialog('批量添加后缀完成');
      },
    );
  }

  // Execute Restore to remove stats suffix
  Future<void> _startRestore() async {
    final list = widget.items.where((item) {
      final hasSuffix = item.currentName != item.baseName;
      return item.isSelected && hasSuffix;
    }).toList();

    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前选择的项目无需还原命名（或者未匹配到统计后缀）')),
      );
      return;
    }

    setState(() {
      _isExecuting = true;
      _progress = 0.0;
      _successCount = 0;
      _failCount = 0;
    });

    await SnifferLogic.executeRestoreNames(
      list,
      onItemComplete: (index, progress, item) {
        setState(() {
          _progress = progress;
          _currentExecutingItem = item.baseName;
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
        _showResultDialog('批量还原名称完成');
      },
    );
  }

  // 导出为 TXT 文件
  Future<void> _exportToTxt() async {
    final selectedItems =
        widget.items.where((item) => item.isSelected).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先勾选需要导出的文件夹')),
      );
      return;
    }

    try {
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '选择保存 TXT 文件的路径',
        fileName:
            'sniffer_results_${DateTime.now().millisecondsSinceEpoch}.txt',
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (outputFile == null) return; // 用户取消

      final buffer = StringBuffer();
      buffer.writeln('================ DocTool 文件嗅探结果导出 ================');
      buffer.writeln(
          '导出时间: ${DateTime.now().toLocal().toString().split('.').first}');
      buffer.writeln('共导出项目数: ${selectedItems.length} 个');
      buffer.writeln('--------------------------------------------------');

      for (int i = 0; i < selectedItems.length; i++) {
        final item = selectedItems[i];
        buffer.writeln('[${i + 1}] 文件夹: ${item.currentName}');
        buffer.writeln('路径: ${item.currentPath}');
        buffer.writeln('总文件数: ${item.totalCount} 个');
        buffer.writeln('总大小: ${item.formattedTotalSize}');
        buffer.writeln('分类统计详情:');

        final videoInfo = item.stats[FileCategory.video] ??
            FileTypeInfo(category: FileCategory.video);
        final imageInfo = item.stats[FileCategory.image] ??
            FileTypeInfo(category: FileCategory.image);
        final archiveInfo = item.stats[FileCategory.archive] ??
            FileTypeInfo(category: FileCategory.archive);
        final docInfo = item.stats[FileCategory.document] ??
            FileTypeInfo(category: FileCategory.document);
        final audioInfo = item.stats[FileCategory.audio] ??
            FileTypeInfo(category: FileCategory.audio);
        final otherInfo = item.stats[FileCategory.other] ??
            FileTypeInfo(category: FileCategory.other);

        buffer.writeln(
            '  - 视频: ${videoInfo.count} 个 (${videoInfo.formattedSize})');
        buffer.writeln(
            '  - 图片: ${imageInfo.count} 张 (${imageInfo.formattedSize})');
        buffer.writeln(
            '  - 压缩包: ${archiveInfo.count} 个 (${archiveInfo.formattedSize})');
        buffer.writeln('  - 文档: ${docInfo.count} 份 (${docInfo.formattedSize})');
        buffer.writeln(
            '  - 音频: ${audioInfo.count} 首 (${audioInfo.formattedSize})');
        buffer.writeln(
            '  - 其他: ${otherInfo.count} 个 (${otherInfo.formattedSize})');
        buffer.writeln('--------------------------------------------------');
      }

      final file = File(outputFile);
      await file.writeAsString(buffer.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出 TXT 成功！')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  // 导出为 Excel 文件
  Future<void> _exportToExcel() async {
    final selectedItems =
        widget.items.where((item) => item.isSelected).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先勾选需要导出的文件夹')),
      );
      return;
    }

    try {
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '选择保存 Excel 文件的路径',
        fileName:
            'sniffer_results_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputFile == null) return; // 用户取消

      var excel = Excel.createExcel();
      var sheetName = excel.sheets.keys.first;
      var sheet = excel[sheetName];

      // 表头
      sheet.appendRow([
        TextCellValue('序号'),
        TextCellValue('文件夹名称'),
        TextCellValue('总文件数'),
        TextCellValue('总大小(字节)'),
        TextCellValue('总大小(格式化)'),
        TextCellValue('视频数量'),
        TextCellValue('视频大小'),
        TextCellValue('图片数量'),
        TextCellValue('图片大小'),
        TextCellValue('压缩包数量'),
        TextCellValue('压缩包大小'),
        TextCellValue('文档数量'),
        TextCellValue('文档大小'),
        TextCellValue('音频数量'),
        TextCellValue('音频大小'),
        TextCellValue('其他数量'),
        TextCellValue('其他大小'),
        TextCellValue('文件夹路径'),
      ]);

      // 写入数据
      for (int i = 0; i < selectedItems.length; i++) {
        final item = selectedItems[i];
        final videoInfo = item.stats[FileCategory.video] ??
            FileTypeInfo(category: FileCategory.video);
        final imageInfo = item.stats[FileCategory.image] ??
            FileTypeInfo(category: FileCategory.image);
        final archiveInfo = item.stats[FileCategory.archive] ??
            FileTypeInfo(category: FileCategory.archive);
        final docInfo = item.stats[FileCategory.document] ??
            FileTypeInfo(category: FileCategory.document);
        final audioInfo = item.stats[FileCategory.audio] ??
            FileTypeInfo(category: FileCategory.audio);
        final otherInfo = item.stats[FileCategory.other] ??
            FileTypeInfo(category: FileCategory.other);

        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(item.currentName),
          IntCellValue(item.totalCount),
          IntCellValue(item.totalSizeBytes),
          TextCellValue(item.formattedTotalSize),
          IntCellValue(videoInfo.count),
          TextCellValue(videoInfo.formattedSize),
          IntCellValue(imageInfo.count),
          TextCellValue(imageInfo.formattedSize),
          IntCellValue(archiveInfo.count),
          TextCellValue(archiveInfo.formattedSize),
          IntCellValue(docInfo.count),
          TextCellValue(docInfo.formattedSize),
          IntCellValue(audioInfo.count),
          TextCellValue(audioInfo.formattedSize),
          IntCellValue(otherInfo.count),
          TextCellValue(otherInfo.formattedSize),
          TextCellValue(item.currentPath),
        ]);
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(outputFile);
        await file.create(recursive: true);
        await file.writeAsBytes(fileBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导出 Excel 成功！')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  void _showResultDialog(String title) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
              color: context.textColorPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '成功：$_successCount 个文件夹\n失败：$_failCount 个文件夹',
          style: TextStyle(color: context.textColorSecondary, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onRenameCompleted();
            },
            child: const Text('确定',
                style: TextStyle(
                    color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Sortable header widget (unified with other tabs)
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
              color: isSelected ? Colors.purpleAccent : Colors.grey,
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
            color: isSelected ? Colors.purpleAccent : Colors.grey[600],
          ),
        ],
      ),
    );
  }

  // UI Helpers for specific categories
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

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case FileCategory.video:
        return Icons.movie_outlined;
      case FileCategory.image:
        return Icons.image_outlined;
      case FileCategory.archive:
        return Icons.archive_outlined;
      case FileCategory.document:
        return Icons.description_outlined;
      case FileCategory.audio:
        return Icons.audiotrack_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    // Sort items by sortColumnIndex
    List<SnifferFolderItem> sortedList = List.from(widget.items);
    if (_sortColumnIndex == 0) {
      sortedList.sort((a, b) {
        int cmp =
            a.currentName.toLowerCase().compareTo(b.currentName.toLowerCase());
        return _sortAscending ? cmp : -cmp;
      });
    } else if (_sortColumnIndex == 1) {
      sortedList.sort((a, b) {
        int cmp = a.totalCount.compareTo(b.totalCount);
        return _sortAscending ? cmp : -cmp;
      });
    } else if (_sortColumnIndex == 2) {
      sortedList.sort((a, b) {
        int cmp = a.totalSizeBytes.compareTo(b.totalSizeBytes);
        return _sortAscending ? cmp : -cmp;
      });
    }

    final allSelected = widget.items.isNotEmpty &&
        widget.items.every((item) => item.isSelected);
    final someSelected =
        widget.items.any((item) => item.isSelected) && !allSelected;

    // Count items with changes, considering selection status
    final changedCount = widget.items
        .where((item) =>
            item.isSelected &&
            item.newName != item.currentName &&
            _getItemValidationError(item) == null)
        .length;

    final selectedCount = widget.items.where((item) => item.isSelected).length;

    final hasRestoreItems = widget.items
        .any((item) => item.isSelected && item.currentName != item.baseName);

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
            // Header: Preview & Execute Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '共 ${widget.items.length} 个子文件夹，已选择 $selectedCount 个，将更改 $changedCount 个',
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
                    backgroundColor: Colors.purpleAccent,
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
                          changedCount == 0)
                      ? null
                      : _startRename,
                  icon: const Icon(Icons.drive_file_rename_outline),
                  label: const Text('追加统计'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.purpleAccent,
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
                PopupMenuButton<String>(
                  key: _moreMenuKey,
                  enabled: !_isExecuting,
                  tooltip: '更多操作',
                  onSelected: (value) {
                    if (value == 'txt') {
                      _exportToTxt();
                    } else if (value == 'excel') {
                      _exportToExcel();
                    } else if (value == 'restore') {
                      _startRestore();
                    }
                  },
                  itemBuilder: (context) {
                    final hasItems = widget.items.isNotEmpty;
                    return [
                      PopupMenuItem(
                        value: 'txt',
                        enabled: hasItems,
                        child: Row(
                          children: [
                            Icon(
                              Icons.description,
                              color: hasItems ? Colors.blue : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text('导出为 TXT'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'excel',
                        enabled: hasItems,
                        child: Row(
                          children: [
                            Icon(
                              Icons.table_chart,
                              color: hasItems ? Colors.green : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text('导出为 Excel'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'restore',
                        enabled: hasItems && hasRestoreItems,
                        child: Row(
                          children: [
                            Icon(
                              Icons.settings_backup_restore,
                              color: (hasItems && hasRestoreItems)
                                  ? Colors.redAccent
                                  : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text('还原名称'),
                          ],
                        ),
                      ),
                    ];
                  },
                  icon: Icon(
                    Icons.more_vert,
                    size: 24,
                    color: !_isExecuting
                        ? context.textColorPrimary
                        : context.textColorSecondary.withOpacity(0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Execution Progress Overlay
            if (_isExecuting) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('正在重命名文件夹...',
                            style: TextStyle(
                                color: context.textColorPrimary,
                                fontWeight: FontWeight.bold)),
                        Text('${(_progress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(color: Colors.purpleAccent)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: context.isDarkMode
                          ? Colors.grey[800]
                          : Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.purpleAccent),
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
            // Column Header with Checkbox + Sortable Headers (总是可见的)
            Container(
              padding:
                  const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 8),
              decoration: BoxDecoration(
                color: context.inputBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: allSelected ? true : (someSelected ? null : false),
                      tristate: true,
                      activeColor: Colors.purpleAccent,
                      onChanged: (val) {
                        final selectAll = val == true;
                        for (var item in widget.items) {
                          item.isSelected = selectAll;
                          widget.onItemSelectionChanged?.call(item.currentPath);
                        }
                        _validateCollisions();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: _buildSortableHeader('文件夹名称', 0),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: _buildSortableHeader('文件数量', 1),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _buildSortableHeader('总大小', 2),
                  ),
                  const SizedBox(width: 90),
                ],
              ),
            ),

            // Expanded Dynamic Content Container
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: context.listBg,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
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
                                      Colors.purpleAccent),
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
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.purpleAccent),
                                  minHeight: 6,
                                ),
                              ),
                              if (widget.scanProgress > 0.0) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '${(widget.scanProgress * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                      color: Colors.purpleAccent,
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
                                  widget.onSearch == null
                                      ? Icons.folder_open
                                      : Icons.saved_search,
                                  size: 48,
                                  color: context.textColorSecondary
                                      .withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  widget.onSearch == null
                                      ? '尚未选择任何目标文件夹\n请点击左上角的“选择”按钮选择文件夹以开始'
                                      : '暂无嗅探数据，请配置规则并点击上方“预览”按钮',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: context.textColorSecondary,
                                      fontSize: 14,
                                      height: 1.5),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: sortedList.length,
                            itemBuilder: (context, index) {
                              final item = sortedList[index];
                              final error = _getItemValidationError(item);
                              final isExpanded =
                                  _expandedPaths.contains(item.currentPath);
                              final hasChanges =
                                  item.newName != item.currentName;

                              return Card(
                                color: isDark
                                    ? const Color(0xFF1E1E22)
                                    : const Color(0xFFF8F9FA),
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: error != null
                                        ? Colors.redAccent
                                        : (hasChanges && item.isSelected
                                            ? Colors.purpleAccent
                                                .withOpacity(0.5)
                                            : context.borderColor),
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    // Main Info Row
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          if (isExpanded) {
                                            _expandedPaths
                                                .remove(item.currentPath);
                                          } else {
                                            _expandedPaths
                                                .add(item.currentPath);
                                          }
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Row(
                                          children: [
                                            // Checkbox
                                            SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: Checkbox(
                                                value: item.isSelected,
                                                activeColor:
                                                    Colors.purpleAccent,
                                                onChanged: (val) {
                                                  item.isSelected =
                                                      val ?? false;
                                                  widget.onItemSelectionChanged
                                                      ?.call(item.currentPath);
                                                  _validateCollisions();
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),

                                            // Folder Info
                                            Expanded(
                                              flex: 5,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Icon(Icons.folder_open,
                                                          size: 16,
                                                          color: Colors
                                                              .amber[700]),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Tooltip(
                                                          message:
                                                              item.currentName,
                                                          child: Text(
                                                            item.currentName,
                                                            style: TextStyle(
                                                              color: context
                                                                  .textColorPrimary,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 13,
                                                              decoration: hasChanges &&
                                                                      item
                                                                          .isSelected
                                                                  ? TextDecoration
                                                                      .lineThrough
                                                                  : null,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  if (hasChanges &&
                                                      item.isSelected) ...[
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        const Icon(
                                                            Icons
                                                                .arrow_right_alt,
                                                            size: 14,
                                                            color: Colors
                                                                .purpleAccent),
                                                        const SizedBox(
                                                            width: 4),
                                                        Expanded(
                                                          child: Tooltip(
                                                            message:
                                                                item.newName,
                                                            child: Text(
                                                              item.newName,
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .purpleAccent,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 12,
                                                              ),
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),

                                            // File Count
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                '${item.totalCount}',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    color: context
                                                        .textColorSecondary,
                                                    fontSize: 12),
                                              ),
                                            ),

                                            // Size
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                item.formattedTotalSize,
                                                style: TextStyle(
                                                    color: context
                                                        .textColorSecondary,
                                                    fontSize: 12),
                                              ),
                                            ),

                                            // Error/Status Badge & Expand Arrow
                                            SizedBox(
                                              width: 90,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  if (error != null)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 3),
                                                      decoration: BoxDecoration(
                                                          color: Colors
                                                              .redAccent
                                                              .withOpacity(0.2),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6)),
                                                      child: Text(error,
                                                          style: const TextStyle(
                                                              color: Colors
                                                                  .redAccent,
                                                              fontSize: 9,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                    )
                                                  else if (!item.isSelected)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 3),
                                                      decoration: BoxDecoration(
                                                          color: context
                                                              .borderColor,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6)),
                                                      child: Text('已排除',
                                                          style: TextStyle(
                                                              color: context
                                                                  .textColorSecondary,
                                                              fontSize: 9)),
                                                    )
                                                  else if (!hasChanges)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 3),
                                                      decoration: BoxDecoration(
                                                          color: Colors
                                                              .greenAccent
                                                              .withOpacity(0.2),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6)),
                                                      child: const Text('已是最优',
                                                          style: TextStyle(
                                                              color:
                                                                  Colors.green,
                                                              fontSize: 9)),
                                                    )
                                                  else
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 3),
                                                      decoration: BoxDecoration(
                                                          color: Colors
                                                              .purpleAccent
                                                              .withOpacity(
                                                                  0.15),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6)),
                                                      child: const Text('待执行',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .purpleAccent,
                                                              fontSize: 9,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                    ),
                                                  const SizedBox(width: 4),
                                                  Icon(
                                                    isExpanded
                                                        ? Icons
                                                            .keyboard_arrow_up
                                                        : Icons
                                                            .keyboard_arrow_down,
                                                    size: 18,
                                                    color: context
                                                        .textColorSecondary,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Visual Stacked Bar Chart
                                    if (item.totalCount > 0)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 8),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildStackedProgressBar(item),
                                            const SizedBox(height: 4),
                                            _buildColorLegendRow(item),
                                          ],
                                        ),
                                      )
                                    else
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 8),
                                        child: Text(
                                          '此文件夹是空文件夹',
                                          style: TextStyle(
                                              color: context.textColorSecondary
                                                  .withOpacity(0.7),
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic),
                                        ),
                                      ),

                                    // Expanded Details (Dropdown panel)
                                    if (isExpanded) ...[
                                      Divider(
                                          height: 1,
                                          color: context.borderColor),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        color: context.listBg.withOpacity(0.3),
                                        child: Column(
                                          children: FileCategory.all
                                              .where((cat) =>
                                                  widget.rule.enabledTypes
                                                      .contains(cat) ||
                                                  (cat == FileCategory.other &&
                                                      widget.rule.enableOther))
                                              .map((cat) {
                                            final activeStats = item
                                                .getActiveStats(widget.rule);
                                            final info = activeStats[cat]!;
                                            if (cat == FileCategory.other &&
                                                widget.rule.hideZero &&
                                                info.count == 0) {
                                              return const SizedBox();
                                            }
                                            final color =
                                                _getCategoryColor(cat);
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4.0),
                                              child: Row(
                                                children: [
                                                  Icon(_getCategoryIcon(cat),
                                                      size: 16, color: color),
                                                  const SizedBox(width: 8),
                                                  Text(cat,
                                                      style: TextStyle(
                                                          color: context
                                                              .textColorPrimary,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600)),
                                                  const Spacer(),
                                                  Text(
                                                    '${info.count}${FileCategory.units[cat]} (${info.formattedSize})',
                                                    style: TextStyle(
                                                        color: context
                                                            .textColorSecondary,
                                                        fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ],
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

  // Build high aesthetics stacked progress bar based on sizeBytes
  Widget _buildStackedProgressBar(SnifferFolderItem item) {
    final double totalBytes = item.totalSizeBytes.toDouble();
    if (totalBytes <= 0) return const SizedBox();

    final List<Widget> bars = [];
    final activeStats = item.getActiveStats(widget.rule);
    for (var cat in FileCategory.all) {
      if (!widget.rule.enabledTypes.contains(cat) &&
          (cat != FileCategory.other || !widget.rule.enableOther)) continue;
      final info = activeStats[cat]!;
      if (info.sizeBytes <= 0) continue;
      final flexVal = ((info.sizeBytes / totalBytes) * 1000).round();
      if (flexVal <= 0) continue;

      bars.add(
        Expanded(
          flex: flexVal,
          child: Tooltip(
            message:
                '$cat: ${info.formattedSize} (${(info.sizeBytes / totalBytes * 100).toStringAsFixed(1)}%)',
            child: Container(
              height: 8,
              color: _getCategoryColor(cat),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Row(children: bars),
    );
  }

  // Row showing type size share info
  Widget _buildColorLegendRow(SnifferFolderItem item) {
    final List<Widget> legend = [];
    final activeStats = item.getActiveStats(widget.rule);
    for (var cat in FileCategory.all) {
      if (!widget.rule.enabledTypes.contains(cat) &&
          (cat != FileCategory.other || !widget.rule.enableOther)) continue;
      final info = activeStats[cat]!;
      if (info.count <= 0) continue;

      legend.add(
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _getCategoryColor(cat),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$cat: ${info.count}${FileCategory.units[cat]}',
                style:
                    TextStyle(fontSize: 10, color: context.textColorSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(children: legend);
  }
}
