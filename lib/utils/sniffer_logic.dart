import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 文件分类大类
class FileCategory {
  static const String video = '视频';
  static const String image = '图片';
  static const String archive = '压缩包';
  static const String document = '文档';
  static const String audio = '音频';
  static const String other = '其他';

  static const List<String> all = [
    video,
    image,
    archive,
    document,
    audio,
    other
  ];

  /// 各大类的默认后缀（不含 .，统一小写）
  static const Map<String, Set<String>> extensions = {
    video: {
      'mp4',
      'mkv',
      'avi',
      'mov',
      'wmv',
      'flv',
      'webm',
      'rmvb',
      'm4v',
      'ts',
      'mts',
      'mpeg',
      'mpg',
      '3gp',
      'vob'
    },
    image: {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
      'svg',
      'ico',
      'tiff',
      'tif',
      'psd',
      'ai',
      'raw',
      'heic'
    },
    archive: {
      'zip',
      'rar',
      '7z',
      'tar',
      'gz',
      'bz2',
      'xz',
      'apk',
      'ipa',
      'dmg',
      'iso',
      'pkg',
      'jar'
    },
    document: {
      'txt',
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'md',
      'csv',
      'epub',
      'mobi',
      'wps',
      'rtf',
      'html',
      'htm',
      'json',
      'yaml',
      'xml'
    },
    audio: {
      'mp3',
      'wav',
      'flac',
      'aac',
      'ogg',
      'm4a',
      'wma',
      'ape',
      'cue',
      'mid',
      'alac'
    },
  };

  /// 各大类的统计默认量词（用于重命名追加信息）
  static const Map<String, String> units = {
    video: '个',
    image: '张',
    archive: '个',
    document: '份',
    audio: '首',
    other: '个',
  };
}

/// 某大类文件的统计信息
class FileTypeInfo {
  final String category;
  int count;
  int sizeBytes;

  FileTypeInfo({
    required this.category,
    this.count = 0,
    this.sizeBytes = 0,
  });

  String get formattedSize {
    if (sizeBytes <= 0) return '0B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = sizeBytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 1 : 2)}${suffixes[i]}';
  }
}

/// 嗅探到的子文件夹项
class SnifferFolderItem {
  final Directory directory;
  final String currentPath;
  final String currentName;
  final String baseName; // 去除统计后缀后的纯净名称
  final Map<String, FileTypeInfo> stats; // 统计数据

  String newName = '';
  String newPath = '';
  String? error;
  bool isSuccess = false;
  bool isSelected = true;

  SnifferFolderItem({
    required this.directory,
    required this.currentPath,
    required this.currentName,
    required this.baseName,
    required this.stats,
  });

  int get totalCount => stats.values.fold(0, (sum, info) => sum + info.count);
  int get totalSizeBytes =>
      stats.values.fold(0, (sum, info) => sum + info.sizeBytes);

  String get formattedTotalSize {
    if (totalSizeBytes <= 0) return '0B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = totalSizeBytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 1 : 2)}${suffixes[i]}';
  }

  /// 获取根据当前规则过滤合并后的文件统计（未启用的类型归入“其他”）
  Map<String, FileTypeInfo> getActiveStats(SnifferRule rule) {
    final Map<String, FileTypeInfo> activeStats = {
      for (var cat in FileCategory.all)
        cat: FileTypeInfo(category: cat, count: 0, sizeBytes: 0)
    };

    for (var cat in FileCategory.all) {
      final originalInfo = stats[cat];
      if (originalInfo == null) continue;

      if (rule.enabledTypes.contains(cat)) {
        activeStats[cat]!.count += originalInfo.count;
        activeStats[cat]!.sizeBytes += originalInfo.sizeBytes;
      } else if (rule.enableOther) {
        activeStats[FileCategory.other]!.count += originalInfo.count;
        activeStats[FileCategory.other]!.sizeBytes += originalInfo.sizeBytes;
      }
    }
    return activeStats;
  }

  /// 重新生成拟重命名的名字和路径
  void updateNewName(SnifferRule rule) {
    if (totalCount == 0 && rule.skipEmptyFolder) {
      newName = baseName;
      newPath = currentPath;
      return;
    }

    final activeStats = getActiveStats(rule);
    final List<String> parts = [];
    for (var cat in FileCategory.all) {
      final bool isEnabled = (cat == FileCategory.other)
          ? rule.enableOther
          : rule.enabledTypes.contains(cat);
      if (!isEnabled) continue;
      final info = activeStats[cat];
      if (info == null) continue;
      if (rule.hideZero && info.count == 0) continue;

      final countStr =
          rule.showCount ? '${info.count}${FileCategory.units[cat]}' : '';
      final sizeStr = rule.showSize ? info.formattedSize : '';

      if (countStr.isNotEmpty && sizeStr.isNotEmpty) {
        parts.add('$cat $countStr($sizeStr)');
      } else if (countStr.isNotEmpty) {
        parts.add('$cat $countStr');
      } else if (sizeStr.isNotEmpty) {
        parts.add('$cat $sizeStr');
      }
    }

    if (parts.isEmpty) {
      newName = baseName;
    } else {
      final String suffix = parts.join(rule.separator);
      newName = '$baseName${rule.wrapperStart}$suffix${rule.wrapperEnd}';
    }

    final parentPath = p.dirname(currentPath);
    newPath = p.join(parentPath, newName);
  }
}

/// 嗅探命名规则配置
class SnifferRule {
  bool recursive; // 统计是否包含子文件夹的子文件
  Set<String> enabledTypes; // 启用的文件大类
  bool enableOther; // 是否统计"其他"类别
  String wrapperStart; // 包裹字符开始，例如 [ 或 (
  String wrapperEnd; // 包裹字符结束，例如 ] 或 )
  String separator; // 拼接分隔符，例如 ,
  bool showSize; // 是否显示大小
  bool showCount; // 是否显示数量
  bool hideZero; // 是否隐藏数量为0的类别
  bool skipEmptyFolder; // 空文件夹是否保持原样

  SnifferRule({
    this.recursive = true,
    Set<String>? enabledTypes,
    this.enableOther = true,
    this.wrapperStart = ' [',
    this.wrapperEnd = ']',
    this.separator = ', ',
    this.showSize = true,
    this.showCount = true,
    this.hideZero = true,
    this.skipEmptyFolder = false,
  }) : enabledTypes = enabledTypes ?? Set.from(FileCategory.all);

  SnifferRule copyWith({
    bool? recursive,
    Set<String>? enabledTypes,
    bool? enableOther,
    String? wrapperStart,
    String? wrapperEnd,
    String? separator,
    bool? showSize,
    bool? showCount,
    bool? hideZero,
    bool? skipEmptyFolder,
  }) {
    return SnifferRule(
      recursive: recursive ?? this.recursive,
      enabledTypes: enabledTypes ?? this.enabledTypes,
      enableOther: enableOther ?? this.enableOther,
      wrapperStart: wrapperStart ?? this.wrapperStart,
      wrapperEnd: wrapperEnd ?? this.wrapperEnd,
      separator: separator ?? this.separator,
      showSize: showSize ?? this.showSize,
      showCount: showCount ?? this.showCount,
      hideZero: hideZero ?? this.hideZero,
      skipEmptyFolder: skipEmptyFolder ?? this.skipEmptyFolder,
    );
  }
}

/// 嗅探核心逻辑
class SnifferLogic {
  /// 提取文件夹原本的纯净名称（去除尾部的各类统计信息括号）
  static String extractBaseName(String dirName, {SnifferRule? rule}) {
    // 1. 如果传入了当前规则，先针对当前的自定义包裹符进行精确的剥离匹配
    if (rule != null) {
      final start = RegExp.escape(rule.wrapperStart.trim());
      final end = RegExp.escape(rule.wrapperEnd.trim());
      if (start.isNotEmpty && end.isNotEmpty) {
        final customRegex = RegExp('\\s*$start.*$end\$');
        if (customRegex.hasMatch(dirName)) {
          return dirName.replaceAll(customRegex, '').trim();
        }
      }
    }

    // 2. 默认保底正则匹配常见括号
    final regex = RegExp(
      r'\s*[\[\(\{][^\]\)\}]*(?:视频|图片|压缩包|文档|音频|其他|个|张|份|首|[kKMGT]?B)[^\]\)\}]*[\]\)\}]$',
      caseSensitive: false,
    );
    if (regex.hasMatch(dirName)) {
      return dirName.replaceAll(regex, '').trim();
    }
    return dirName;
  }

  /// 扫描目标目录的一级子目录，并统计每个子目录中的文件情况
  static Future<List<SnifferFolderItem>> scanDirectoriesForSniff({
    required String rootPath,
    required SnifferRule rule,
    required void Function(double progress, String status) onProgress,
  }) async {
    final List<SnifferFolderItem> results = [];
    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      return results;
    }

    try {
      onProgress(0.05, '正在读取文件夹列表...');
      final List<FileSystemEntity> firstLevelEntities =
          await dir.list(recursive: false, followLinks: false).toList();
      final List<Directory> subDirs =
          firstLevelEntities.whereType<Directory>().toList();

      if (subDirs.isEmpty) {
        onProgress(1.0, '未发现任何子文件夹');
        return results;
      }

      int completedCount = 0;
      final int maxConcurrency = Platform.numberOfProcessors * 2;
      final List<SnifferFolderItem?> folderResults =
          List.filled(subDirs.length, null);

      int activeWorkers = 0;
      int nextIndex = 0;
      final completer = Completer<void>();

      void launchWorker() {
        if (nextIndex >= subDirs.length) {
          if (activeWorkers == 0 && !completer.isCompleted) {
            completer.complete();
          }
          return;
        }

        final index = nextIndex++;
        activeWorkers++;

        _processSubDir(subDirs[index], rule).then((item) {
          folderResults[index] = item;
          completedCount++;
          onProgress(
            0.05 + 0.95 * (completedCount / subDirs.length),
            '正在统计子文件夹: ${item.currentName} ($completedCount/${subDirs.length})',
          );
        }).whenComplete(() {
          activeWorkers--;
          launchWorker();
        });
      }

      final initialWorkers = maxConcurrency < subDirs.length
          ? maxConcurrency
          : subDirs.length;
      for (int i = 0; i < initialWorkers; i++) {
        launchWorker();
      }

      await completer.future;

      results.addAll(folderResults.whereType<SnifferFolderItem>());

      onProgress(1.0, '扫描完成，共找到 ${results.length} 个文件夹');
    } catch (e) {
      debugPrint('Sniffer scan error: $e');
      onProgress(1.0, '扫描出错: $e');
    }

    return results;
  }

  /// Helper to process a single subdirectory concurrently
  static Future<SnifferFolderItem> _processSubDir(
      Directory subDir, SnifferRule rule) async {
    final dirPath = subDir.path;
    final dirName = p.basename(dirPath);
    final baseName = extractBaseName(dirName, rule: rule);

    final Map<String, FileTypeInfo> stats = {
      for (var cat in FileCategory.all) cat: FileTypeInfo(category: cat)
    };

    try {
      final List<FileSystemEntity> allEntities = await subDir
          .list(recursive: rule.recursive, followLinks: false)
          .toList();

      for (var entity in allEntities) {
        if (entity is File) {
          final filePath = entity.path;
          final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
          int size = 0;
          try {
            final stat = await entity.stat();
            size = stat.size;
          } catch (e) {
            debugPrint('Warning: Unable to get stat of $filePath: $e');
          }

          String assignedCategory = FileCategory.other;
          for (var entry in FileCategory.extensions.entries) {
            if (entry.value.contains(ext)) {
              assignedCategory = entry.key;
              break;
            }
          }

          stats[assignedCategory]!.count++;
          stats[assignedCategory]!.sizeBytes += size;
        }
      }
    } catch (e) {
      debugPrint('Error listing subdirectory $dirPath: $e');
    }

    final item = SnifferFolderItem(
      directory: subDir,
      currentPath: dirPath,
      currentName: dirName,
      baseName: baseName,
      stats: stats,
    );
    item.updateNewName(rule);
    return item;
  }

  /// 执行嗅探重命名
  static Future<void> executeSnifferRename(
    List<SnifferFolderItem> items, {
    required void Function(int index, double progress, SnifferFolderItem item)
        onItemComplete,
    required void Function() onAllComplete,
  }) async {
    if (items.isEmpty) {
      onAllComplete();
      return;
    }

    final sortedItems = List<SnifferFolderItem>.from(items);
    sortedItems.sort((a, b) {
      final aParts = p.split(a.currentPath).length;
      final bParts = p.split(b.currentPath).length;
      return bParts.compareTo(aParts);
    });

    for (int i = 0; i < sortedItems.length; i++) {
      final item = sortedItems[i];
      if (!item.isSelected) {
        item.isSuccess = true;
        onItemComplete(i, (i + 1) / sortedItems.length, item);
        continue;
      }

      if (item.newName.isEmpty || item.newName == item.currentName) {
        item.isSuccess = true;
        onItemComplete(i, (i + 1) / sortedItems.length, item);
        continue;
      }

      if (_hasInvalidChars(item.newName)) {
        item.isSuccess = false;
        item.error = '包含非法字符';
        onItemComplete(i, (i + 1) / sortedItems.length, item);
        continue;
      }

      try {
        if (await item.directory.exists()) {
          if (await FileSystemEntity.type(item.newPath) !=
              FileSystemEntityType.notFound) {
            item.isSuccess = false;
            item.error = '目标路径已存在';
          } else {
            await item.directory.rename(item.newPath);
            item.isSuccess = true;
          }
        } else {
          item.isSuccess = false;
          item.error = '源文件夹不存在';
        }
      } catch (e) {
        item.isSuccess = false;
        item.error = e.toString();
      }

      onItemComplete(i, (i + 1) / sortedItems.length, item);
    }
    onAllComplete();
  }

  /// 还原命名（一键去掉尾部的统计后缀）
  static Future<void> executeRestoreNames(
    List<SnifferFolderItem> items, {
    required void Function(int index, double progress, SnifferFolderItem item)
        onItemComplete,
    required void Function() onAllComplete,
  }) async {
    if (items.isEmpty) {
      onAllComplete();
      return;
    }

    final sortedItems = List<SnifferFolderItem>.from(items);
    sortedItems.sort((a, b) {
      final aParts = p.split(a.currentPath).length;
      final bParts = p.split(b.currentPath).length;
      return bParts.compareTo(aParts);
    });

    for (int i = 0; i < sortedItems.length; i++) {
      final item = sortedItems[i];
      if (!item.isSelected) {
        item.isSuccess = true;
        onItemComplete(i, (i + 1) / sortedItems.length, item);
        continue;
      }

      if (item.currentName == item.baseName) {
        item.isSuccess = true;
        onItemComplete(i, (i + 1) / sortedItems.length, item);
        continue;
      }

      final parentPath = p.dirname(item.currentPath);
      final restoredPath = p.join(parentPath, item.baseName);

      try {
        if (await item.directory.exists()) {
          if (await FileSystemEntity.type(restoredPath) !=
              FileSystemEntityType.notFound) {
            item.isSuccess = false;
            item.error = '还原路径已存在同名文件夹';
          } else {
            await item.directory.rename(restoredPath);
            item.isSuccess = true;
          }
        } else {
          item.isSuccess = false;
          item.error = '文件夹不存在';
        }
      } catch (e) {
        item.isSuccess = false;
        item.error = e.toString();
      }

      onItemComplete(i, (i + 1) / sortedItems.length, item);
    }
    onAllComplete();
  }

  static bool _hasInvalidChars(String name) {
    if (Platform.isWindows) {
      final invalidChars = RegExp(r'[\\/:*?"<>|]');
      return invalidChars.hasMatch(name);
    } else {
      return name.contains('/');
    }
  }
}
