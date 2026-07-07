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
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      
      // If name hasn't changed, skip but mark as success
      if (item.newName.isEmpty || item.newName == item.baseName) {
        item.isSuccess = true;
        onItemComplete(i, (i + 1) / items.length, item);
        continue;
      }

      // Check for name validity
      if (_hasInvalidChars(item.newName)) {
        item.isSuccess = false;
        item.error = '包含非法字符';
        onItemComplete(i, (i + 1) / items.length, item);
        continue;
      }

      try {
        if (await item.entity.exists()) {
          // Check if target file already exists
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

      onItemComplete(i, (i + 1) / items.length, item);
    }
    onAllComplete();
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
