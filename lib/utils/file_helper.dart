import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';


class RenameItem {
  final FileSystemEntity entity;
  final String currentPath;
  final String currentName;
  final String baseName;
  final String extension;
  final String parentPath;
  final String parentDirName;
  final bool isDirectory;
  
  String newName;
  String newPath;
  String? error;
  bool isSuccess;

  RenameItem({
    required this.entity,
    required this.currentPath,
    required this.currentName,
    required this.baseName,
    required this.extension,
    required this.parentPath,
    required this.parentDirName,
    required this.isDirectory,
    this.newName = '',
    this.newPath = '',
    this.error,
    this.isSuccess = false,
  });

  void updateNewName(String name) {
    newName = name;
    if (isDirectory) {
      newPath = p.join(parentPath, newName);
    } else {
      newPath = p.join(parentPath, newName + extension);
    }
  }
}

class FileHelper {
  /// Open file or folder in system default explorer/viewer
  static Future<void> openFileOrFolder(String path) async {
    if (kIsWeb) return;
    try {
      if (Platform.isWindows) {
        final file = File(path);
        final directory = Directory(path);
        
        if (await directory.exists() || await file.exists()) {
          // Process.run handles parameters correctly even if there are spaces.
          await Process.run('explorer.exe', [path]);
        } else {
          // If the file/folder doesn't exist, open its parent directory
          final parent = p.dirname(path);
          if (await Directory(parent).exists()) {
            await Process.run('explorer.exe', [parent]);
          }
        }
      } else if (Platform.isAndroid) {
        debugPrint('Open path on Android is not implemented natively: $path');
      }
    } catch (e) {
      debugPrint('Error opening path: $e');
    }
  }

  /// Locate file in Windows Explorer (open folder and select file)
  static Future<void> locateInExplorer(String path) async {
    if (kIsWeb) return;
    try {
      if (Platform.isWindows) {
        final file = File(path);
        if (await file.exists()) {
          await Process.run('explorer.exe', ['/select,', path]);
        } else {
          final directory = Directory(path);
          if (await directory.exists()) {
            await Process.run('explorer.exe', [path]);
          }
        }
      }
    } catch (e) {
      debugPrint('Error locating path: $e');
    }
  }

  /// Request Android manage external storage permission
  static Future<bool> requestStoragePermission() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      // For Android 11+ (API 30+), we need MANAGE_EXTERNAL_STORAGE
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) {
        return true;
      }
      
      // Fallback/App settings guidance
      return await Permission.manageExternalStorage.isGranted;
    }
    return true; // Windows does not require this permission
  }

  /// Scan directory for files or folders
  static Future<List<RenameItem>> scanDirectory({
    required String rootPath,
    required bool isFileTarget,
    required bool recursive,
    required String extensionFilter, // comma-separated e.g. "mp4, txt" or "*" for all
  }) async {
    final List<RenameItem> items = [];
    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      return items;
    }

    // Process extension filter
    List<String> allowedExtensions = [];
    if (isFileTarget && extensionFilter.trim().isNotEmpty && extensionFilter.trim() != '*') {
      allowedExtensions = extensionFilter
          .split(',')
          .map((ext) {
            String clean = ext.trim().toLowerCase();
            if (!clean.startsWith('.') && clean.isNotEmpty) {
              clean = '.$clean';
            }
            return clean;
          })
          .where((ext) => ext.isNotEmpty)
          .toList();
    }

    try {
      final List<FileSystemEntity> entities = await dir.list(recursive: recursive, followLinks: false).toList();

      for (var entity in entities) {
        final path = entity.path;
        final name = p.basename(path);
        
        final isDir = entity is Directory;
        
        if (isFileTarget && entity is File) {
          final ext = p.extension(path);
          final base = p.basenameWithoutExtension(path);
          
          // Extension filter
          if (allowedExtensions.isNotEmpty) {
            if (!allowedExtensions.contains(ext.toLowerCase())) {
              continue;
            }
          }

          final parentPath = p.dirname(path);
          final parentDirName = p.basename(parentPath);

          items.add(RenameItem(
            entity: entity,
            currentPath: path,
            currentName: name,
            baseName: base,
            extension: ext,
            parentPath: parentPath,
            parentDirName: parentDirName,
            isDirectory: false,
          ));
        } else if (!isFileTarget && isDir) {
          // Folder rename. Make sure we don't rename the root folder itself!
          if (p.equals(path, rootPath)) {
            continue;
          }

          final parentPath = p.dirname(path);
          final parentDirName = p.basename(parentPath);

          items.add(RenameItem(
            entity: entity,
            currentPath: path,
            currentName: name,
            baseName: name,
            extension: '',
            parentPath: parentPath,
            parentDirName: parentDirName,
            isDirectory: true,
          ));
        }
      }
    } catch (e) {
      debugPrint('Scan error: $e');
    }

    // Sort items by depth (descending) if we are doing recursive directory renaming
    // to avoid renaming parent directories before their children.
    if (!isFileTarget && recursive) {
      items.sort((a, b) {
        final aParts = p.split(a.currentPath).length;
        final bParts = p.split(b.currentPath).length;
        return bParts.compareTo(aParts); // deeper directories first
      });
    }

    return items;
  }

  /// Execute batch rename operation with progress callbacks
  static Future<void> executeRename(
    List<RenameItem> items, {
    required void Function(int index, double progress, RenameItem item) onItemComplete,
    required void Function() onAllComplete,
  }) async {
    if (items.isEmpty) {
      onAllComplete();
      return;
    }

    final hasDirectory = items.any((item) => item.isDirectory);

    if (hasDirectory) {
      // 包含文件夹：为了避免层级目录命名冲突，使用串行重命名
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        await _renameSingleItem(item);
        onItemComplete(i, (i + 1) / items.length, item);
      }
    } else {
      // 纯文件：使用并发协程（Future.wait）执行，提升处理速度
      int completedCount = 0;
      final List<Future<void>> futures = [];
      
      Future<void> renameWorker(int index, RenameItem item) async {
        await _renameSingleItem(item);
        completedCount++;
        onItemComplete(index, completedCount / items.length, item);
      }

      for (int i = 0; i < items.length; i++) {
        futures.add(renameWorker(i, items[i]));
      }
      await Future.wait(futures);
    }
    onAllComplete();
  }

  /// 辅助方法：对单个文件/文件夹执行重命名操作和校验
  static Future<void> _renameSingleItem(RenameItem item) async {
    // 若名称未改变，则跳过并标记成功
    if (item.newName.isEmpty || item.newName == item.baseName) {
      item.isSuccess = true;
      return;
    }

    // 校验非法字符
    if (_hasInvalidChars(item.newName)) {
      item.isSuccess = false;
      item.error = '包含非法字符';
      return;
    }

    try {
      if (await item.entity.exists()) {
        // 校验目标路径是否已存在同名项目
        if (await FileSystemEntity.type(item.newPath) != FileSystemEntityType.notFound) {
          item.isSuccess = false;
          item.error = '目标路径已存在同名项目';
        } else {
          await item.entity.rename(item.newPath);
          item.isSuccess = true;
        }
      } else {
        item.isSuccess = false;
        item.error = '源文件不存在';
      }
    } catch (e) {
      item.isSuccess = false;
      item.error = e.toString();
    }
  }


  static bool _hasInvalidChars(String name) {
    if (Platform.isWindows) {
      // Windows forbidden characters: \ / : * ? " < > |
      final invalidChars = RegExp(r'[\\/:*?"<>|]');
      return invalidChars.hasMatch(name);
    } else {
      // Android/Linux forbidden: /
      return name.contains('/');
    }
  }
}
