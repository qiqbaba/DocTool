import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../utils/theme_helper.dart';

class AndroidDirPicker extends StatefulWidget {
  final String initialPath;

  const AndroidDirPicker({
    super.key,
    this.initialPath = '/storage/emulated/0',
  });

  @override
  State<AndroidDirPicker> createState() => _AndroidDirPickerState();
}

class _AndroidDirPickerState extends State<AndroidDirPicker> {
  late String _currentPath;
  List<Directory> _subDirs = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        throw Exception('目录不存在');
      }

      final List<FileSystemEntity> entities = await dir.list(followLinks: false).toList();
      final List<Directory> dirs = entities
          .whereType<Directory>()
          .where((d) => !p.basename(d.path).startsWith('.')) // hide dot folders
          .toList();

      // Sort alphabetically
      dirs.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));

      setState(() {
        _currentPath = path;
        _subDirs = dirs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '无法访问此文件夹\n(可能是受系统保护或无权限)';
        _isLoading = false;
      });
    }
  }

  void _goUp() {
    if (_currentPath == '/storage/emulated/0' || _currentPath == '/') {
      return;
    }
    final parent = p.dirname(_currentPath);
    _loadDirectory(parent);
  }

  List<Map<String, String>> _getBreadcrumbs() {
    final List<Map<String, String>> crumbs = [];
    crumbs.add({'name': '内部存储', 'path': '/storage/emulated/0'});

    if (_currentPath.startsWith('/storage/emulated/0')) {
      final relative = _currentPath.substring('/storage/emulated/0'.length);
      final parts = p.split(relative).where((part) => part.isNotEmpty && part != '/').toList();
      
      String currentAccumulated = '/storage/emulated/0';
      for (var part in parts) {
        currentAccumulated = p.join(currentAccumulated, part);
        crumbs.add({'name': part, 'path': currentAccumulated});
      }
    } else {
      // For general root path traversal
      final parts = p.split(_currentPath).where((part) => part.isNotEmpty && part != '/').toList();
      String currentAccumulated = '';
      for (var part in parts) {
        currentAccumulated = '$currentAccumulated/$part';
        crumbs.add({'name': part, 'path': currentAccumulated});
      }
    }
    return crumbs;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breadcrumbs = _getBreadcrumbs();

    return Dialog(
      backgroundColor: context.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Close Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '选择文件夹',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: context.textColorPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: context.textColorSecondary),
                  onPressed: () => Navigator.pop(context, null),
                ),
              ],
            ),
            const SizedBox(height: 10),
            
            // Breadcrumbs navigation (horizontal scroll)
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: breadcrumbs.length,
                itemBuilder: (context, index) {
                  final crumb = breadcrumbs[index];
                  final isLast = index == breadcrumbs.length - 1;
                  return Row(
                    children: [
                      GestureDetector(
                        onTap: () => _loadDirectory(crumb['path']!),
                        child: Text(
                          crumb['name']!,
                          style: TextStyle(
                            color: isLast ? theme.colorScheme.primary : context.textColorSecondary,
                            fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (!isLast)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: Icon(Icons.chevron_right, size: 16, color: context.textColorSecondary),
                        ),
                    ],
                  );
                },
              ),
            ),
            Divider(color: context.borderColor, height: 1),
            
            // Subdirectories List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: context.textColorSecondary),
                              ),
                              const SizedBox(height: 16),
                              if (_currentPath != '/storage/emulated/0')
                                ElevatedButton.icon(
                                  onPressed: _goUp,
                                  icon: const Icon(Icons.arrow_upward),
                                  label: const Text('返回上一级'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        )
                      : _subDirs.isEmpty
                          ? Center(
                              child: Text(
                                '空文件夹',
                                style: TextStyle(color: context.textColorSecondary),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _subDirs.length,
                              itemBuilder: (context, index) {
                                final dir = _subDirs[index];
                                final name = p.basename(dir.path);
                                return ListTile(
                                  leading: const Icon(Icons.folder, color: Colors.amber),
                                  title: Text(
                                    name,
                                    style: TextStyle(color: context.textColorPrimary),
                                  ),
                                  onTap: () => _loadDirectory(dir.path),
                                );
                              },
                            ),
            ),
            
            Divider(color: context.borderColor, height: 1),
            const SizedBox(height: 15),
            
            // Bottom Action Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Up Button
                TextButton.icon(
                  onPressed: (_currentPath == '/storage/emulated/0' || _currentPath == '/')
                      ? null
                      : _goUp,
                  icon: const Icon(Icons.arrow_upward),
                  label: const Text('返回上一级'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.textColorSecondary,
                    disabledForegroundColor: context.isDarkMode ? Colors.grey[800] : Colors.grey[300],
                  ),
                ),
                
                // Confirm Selection Button
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _currentPath),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('选择当前文件夹'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
