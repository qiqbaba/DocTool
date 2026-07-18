import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'hash_cache_manager.dart';
import 'file_hash_utils.dart';

enum MoveTarget { file, folder, both }

enum SizeCondition { any, greaterThan, lessThan, equalTo }

enum TimeCondition { any, beforeDate, afterDate, olderThanDays }

enum ConflictStrategy { autoRename, overwrite, skip }

class MoveFilterRule {
  final MoveTarget target;
  final String extensionFilter; // comma-separated e.g. "mp4, txt"
  final String nameContains;
  final bool caseSensitive;

  // Size Filter
  final SizeCondition sizeCondition;
  final int sizeValueBytes;

  // Hash Filter
  final String targetHash; // MD5 string (trimmed)
  final int? targetHashSize; // Filesize of target hash for quick filtering
  final int maxThreads; // Max concurrency threads for hashing (0 = adaptive)

  // Special/Shortcut Filters
  final bool emptyFilesOnly;
  final bool emptyFoldersOnly;
  final bool duplicateFilesOnly;

  // Time Filter
  final TimeCondition timeCondition;
  final DateTime? timeDate;
  final int timeDays;

  // Move-specific Options
  final bool keepStructure; // Whether to keep relative directory structure
  final bool
      flattenToRoot; // Whether to move all nested files to source root and delete empty folders
  final bool
      deleteSpecifiedSizeFiles; // Whether to delete specified size files during move
  final int deleteSizeLimitBytes; // Size limit in bytes for auto-deletion

  MoveFilterRule({
    this.target = MoveTarget.file,
    this.extensionFilter = '',
    this.nameContains = '',
    this.caseSensitive = false,
    this.sizeCondition = SizeCondition.any,
    this.sizeValueBytes = 0,
    this.targetHash = '',
    this.targetHashSize,
    this.maxThreads = 0,
    this.emptyFilesOnly = false,
    this.emptyFoldersOnly = false,
    this.duplicateFilesOnly = false,
    this.timeCondition = TimeCondition.any,
    this.timeDate,
    this.timeDays = 30,
    this.keepStructure = true,
    this.flattenToRoot = false,
    this.deleteSpecifiedSizeFiles = false,
    this.deleteSizeLimitBytes = 1024,
  });

  MoveFilterRule copyWith({
    MoveTarget? target,
    String? extensionFilter,
    String? nameContains,
    bool? caseSensitive,
    SizeCondition? sizeCondition,
    int? sizeValueBytes,
    String? targetHash,
    int? targetHashSize,
    int? maxThreads,
    bool? emptyFilesOnly,
    bool? emptyFoldersOnly,
    bool? duplicateFilesOnly,
    TimeCondition? timeCondition,
    DateTime? timeDate,
    int? timeDays,
    bool? keepStructure,
    bool? flattenToRoot,
    bool? deleteSpecifiedSizeFiles,
    int? deleteSizeLimitBytes,
  }) {
    return MoveFilterRule(
      target: target ?? this.target,
      extensionFilter: extensionFilter ?? this.extensionFilter,
      nameContains: nameContains ?? this.nameContains,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      sizeCondition: sizeCondition ?? this.sizeCondition,
      sizeValueBytes: sizeValueBytes ?? this.sizeValueBytes,
      targetHash: targetHash ?? this.targetHash,
      targetHashSize: targetHashSize ?? this.targetHashSize,
      maxThreads: maxThreads ?? this.maxThreads,
      emptyFilesOnly: emptyFilesOnly ?? this.emptyFilesOnly,
      emptyFoldersOnly: emptyFoldersOnly ?? this.emptyFoldersOnly,
      duplicateFilesOnly: duplicateFilesOnly ?? this.duplicateFilesOnly,
      timeCondition: timeCondition ?? this.timeCondition,
      timeDate: timeDate ?? this.timeDate,
      timeDays: timeDays ?? this.timeDays,
      keepStructure: keepStructure ?? this.keepStructure,
      flattenToRoot: flattenToRoot ?? this.flattenToRoot,
      deleteSpecifiedSizeFiles:
          deleteSpecifiedSizeFiles ?? this.deleteSpecifiedSizeFiles,
      deleteSizeLimitBytes: deleteSizeLimitBytes ?? this.deleteSizeLimitBytes,
    );
  }
}

class MoveItem {
  final FileSystemEntity entity;
  final String path;
  final String name;
  final bool isDirectory;
  final int size; // bytes
  final DateTime lastModified;
  String? md5Hash;
  String?
      quickHash; // Quick hash for partial content match (e.g. first/last 8KB)

  bool isSelected;
  String matchReason;
  bool isMoved;
  String? error;
  String?
      targetPath; // Planned destination path, filled before or during execution

  MoveItem({
    required this.entity,
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.lastModified,
    this.md5Hash,
    this.quickHash,
    this.isSelected = true,
    this.matchReason = '',
    this.isMoved = false,
    this.error,
    this.targetPath,
  });
}

class MoveLogic {
  /// Parallel calculate MD5 for multiple files with concurrency limit.
  /// Delegates to [FileHashUtils] for implementation.
  static Future<Map<String, String>> calculateMd5ForFilesParallel(
    List<File> files, {
    int? concurrencyLimit,
    void Function(int completed, int total)? onProgress,
  }) {
    return FileHashUtils.calculateMd5ForFilesParallel(
      files,
      concurrencyLimit: concurrencyLimit,
      onProgress: onProgress,
    );
  }

  /// Parallel calculate Quick Hash for multiple files with concurrency limit.
  static Future<Map<String, String>> calculateQuickHashForFilesParallel(
    List<File> files, {
    int? concurrencyLimit,
    void Function(int completed, int total)? onProgress,
  }) {
    return FileHashUtils.calculateQuickHashForFilesParallel(
      files,
      concurrencyLimit: concurrencyLimit,
      onProgress: onProgress,
    );
  }

  /// Calculate the MD5 hash of a file.
  static Future<String> calculateFileMd5(File file) {
    return FileHashUtils.calculateFileMd5(file);
  }

  /// Detect if target path resides on a spinning Hard Disk Drive (HDD) on Windows.
  static Future<bool> isDriveHDD(String path) {
    return FileHashUtils.isDriveHDD(path);
  }

  /// Check if a directory is empty.
  static Future<bool> isDirectoryEmpty(Directory dir) {
    return FileHashUtils.isDirectoryEmpty(dir);
  }

  /// Get the total size of a directory recursively.
  static Future<int> getDirectorySize(Directory dir) {
    return FileHashUtils.getDirectorySize(dir);
  }

  /// Scan the folder and apply rules to filter items to be moved
  static Future<List<MoveItem>> scanForMove({
    required String rootPath,
    required MoveFilterRule rule,
    required bool recursive,
    int? maxThreads,
    void Function(double progress, String status)? onProgress,
  }) async {
    final List<MoveItem> items = [];
    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      return items;
    }

    final hashCache = HashCacheManager();
    await hashCache.init();

    int threads = Platform.numberOfProcessors;
    if (rule.maxThreads > 0) {
      threads = rule.maxThreads;
    } else if (maxThreads != null) {
      threads = maxThreads;
    } else {
      final isHDD = await isDriveHDD(rootPath);
      if (isHDD) {
        threads = 1;
      }
    }

    List<String> allowedExtensions = [];
    if (rule.extensionFilter.trim().isNotEmpty &&
        rule.extensionFilter.trim() != '*') {
      allowedExtensions = rule.extensionFilter
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

    final hasPhase2 = rule.targetHash.trim().isNotEmpty;
    final hasPhase3 = rule.duplicateFilesOnly;
    const double w1 = 4.0;
    final double w2 = hasPhase2 ? 3.0 : 0.0;
    final double w3 = hasPhase3 ? 3.0 : 0.0;
    final double totalWeight = w1 + w2 + w3;

    onProgress?.call(0.0, '正在获取文件列表...');

    try {
      final bool actualRecursive = rule.flattenToRoot ? true : recursive;
      final List<FileSystemEntity> entities = await dir
          .list(recursive: actualRecursive, followLinks: false)
          .toList();

      if (entities.isEmpty) {
        onProgress?.call(1.0, '扫描完成，未发现文件');
        await hashCache.save();
        return items;
      }

      // Pre-calculate directory sizes and stats via O(N) Bottom-Up aggregation to avoid O(N^2) directory re-scans
      final Map<String, int> dirSizeMap = {};
      final Map<String, FileStat> statMap = {};
      final Map<String, int> fileSizeMap = {};

      for (var entity in entities) {
        try {
          final stat = await entity.stat();
          statMap[entity.path] = stat;
          if (entity is File) {
            final size = stat.size;
            fileSizeMap[entity.path] = size;
            String parent = p.dirname(entity.path);
            while (parent.length >= rootPath.length) {
              dirSizeMap[parent] = (dirSizeMap[parent] ?? 0) + size;
              final nextParent = p.dirname(parent);
              if (nextParent == parent) break;
              parent = nextParent;
            }
          }
        } catch (e) {
          // Ignore inaccessible files
        }
      }

      List<MoveItem> candidateFiles = [];
      final List<MoveItem> pendingHashFilterItems = [];

      final normalizedRootPath = p.normalize(rootPath);

      for (int i = 0; i < entities.length; i++) {
        final entity = entities[i];

        if (i % 20 == 0 || i == entities.length - 1) {
          final progress = (i / entities.length) * (w1 / totalWeight);
          onProgress?.call(progress, '正在分析文件属性: ${i + 1}/${entities.length}');
        }
        final path = entity.path;
        final name = p.basename(path);

        if (p.equals(path, rootPath)) {
          continue;
        }

        final isDir = entity is Directory;

        if (rule.flattenToRoot) {
          if (isDir) {
            continue;
          }
        }

        if (isDir) {
          if (rule.duplicateFilesOnly) {
            continue;
          }
          if (rule.target == MoveTarget.file) {
            continue;
          }

          bool matched = true;
          List<String> reasons = [];

          final isEmpty = (dirSizeMap[path] ?? 0) == 0 &&
              await isDirectoryEmpty(entity);
          if (rule.emptyFoldersOnly) {
            if (!isEmpty) {
              matched = false;
            } else {
              reasons.add('空文件夹');
            }
          }

          if (matched && rule.nameContains.isNotEmpty) {
            final matchText = rule.caseSensitive
                ? rule.nameContains
                : rule.nameContains.toLowerCase();
            final testName = rule.caseSensitive ? name : name.toLowerCase();
            if (!testName.contains(matchText)) {
              matched = false;
            } else {
              reasons.add('名称包含 "${rule.nameContains}"');
            }
          }

          final int dirSize = dirSizeMap[path] ?? 0;
          if (matched && rule.sizeCondition != SizeCondition.any) {
            switch (rule.sizeCondition) {
              case SizeCondition.greaterThan:
                if (dirSize <= rule.sizeValueBytes) matched = false;
                break;
              case SizeCondition.lessThan:
                if (dirSize >= rule.sizeValueBytes) matched = false;
                break;
              case SizeCondition.equalTo:
                if (dirSize != rule.sizeValueBytes) matched = false;
                break;
              default:
                break;
            }
            if (matched) {
              reasons.add('文件夹大小匹配');
            }
          }

          DateTime modified = DateTime.now();
          if (matched) {
            try {
              final stat = statMap[path] ?? await entity.stat();
              modified = stat.modified;
              if (rule.timeCondition != TimeCondition.any) {
                if (rule.timeCondition == TimeCondition.beforeDate &&
                    rule.timeDate != null) {
                  if (!modified.isBefore(rule.timeDate!)) matched = false;
                } else if (rule.timeCondition == TimeCondition.afterDate &&
                    rule.timeDate != null) {
                  if (!modified.isAfter(rule.timeDate!)) matched = false;
                } else if (rule.timeCondition == TimeCondition.olderThanDays) {
                  final cutoff =
                      DateTime.now().subtract(Duration(days: rule.timeDays));
                  if (!modified.isBefore(cutoff)) matched = false;
                }
                if (matched) {
                  reasons.add('修改时间匹配');
                }
              }
            } catch (e) {
              // Ignore
            }
          }

          if (matched && reasons.isEmpty) {
            reasons.add('文件夹对象');
          }

          if (matched) {
            items.add(MoveItem(
              entity: entity,
              path: path,
              name: name,
              isDirectory: true,
              size: dirSize,
              lastModified: modified,
              matchReason: reasons.join(', '),
            ));
          }
        } else if (entity is File) {
          if (rule.target == MoveTarget.folder) {
            continue;
          }

          final stat = statMap[path] ?? await entity.stat();
          final fileSize = fileSizeMap[path] ?? stat.size;
          final modified = stat.modified;

          final bool shouldAutoDelete = rule.deleteSpecifiedSizeFiles &&
              fileSize < rule.deleteSizeLimitBytes;

          if (rule.flattenToRoot) {
            if (!shouldAutoDelete &&
                p.equals(p.dirname(path), normalizedRootPath)) {
              continue;
            }
          }

          bool matched = true;
          List<String> reasons = [];

          if (shouldAutoDelete) {
            reasons.add(
                '自动删除 (大小 < ${FileHashUtils.formatSizeForReason(rule.deleteSizeLimitBytes)})');
          } else {
            if (rule.emptyFilesOnly) {
              if (fileSize > 0) {
                matched = false;
              } else {
                reasons.add('空文件');
              }
            }

            if (matched && allowedExtensions.isNotEmpty) {
              final ext = p.extension(path).toLowerCase();
              if (!allowedExtensions.contains(ext)) {
                matched = false;
              } else {
                reasons.add('格式匹配: ${ext.replaceFirst('.', '')}');
              }
            }

            if (matched && rule.nameContains.isNotEmpty) {
              final matchText = rule.caseSensitive
                  ? rule.nameContains
                  : rule.nameContains.toLowerCase();
              final testName = rule.caseSensitive ? name : name.toLowerCase();
              if (!testName.contains(matchText)) {
                matched = false;
              } else {
                reasons.add('名称包含 "${rule.nameContains}"');
              }
            }

            if (matched && rule.sizeCondition != SizeCondition.any) {
              switch (rule.sizeCondition) {
                case SizeCondition.greaterThan:
                  if (fileSize <= rule.sizeValueBytes) matched = false;
                  break;
                case SizeCondition.lessThan:
                  if (fileSize >= rule.sizeValueBytes) matched = false;
                  break;
                case SizeCondition.equalTo:
                  if (fileSize != rule.sizeValueBytes) matched = false;
                  break;
                default:
                  break;
              }
              if (matched) {
                reasons.add('大小匹配');
              }
            }

            if (matched && rule.timeCondition != TimeCondition.any) {
              if (rule.timeCondition == TimeCondition.beforeDate &&
                  rule.timeDate != null) {
                if (!modified.isBefore(rule.timeDate!)) matched = false;
              } else if (rule.timeCondition == TimeCondition.afterDate &&
                  rule.timeDate != null) {
                if (!modified.isAfter(rule.timeDate!)) matched = false;
              } else if (rule.timeCondition == TimeCondition.olderThanDays) {
                final cutoff =
                    DateTime.now().subtract(Duration(days: rule.timeDays));
                if (!modified.isBefore(cutoff)) matched = false;
              }
              if (matched) {
                reasons.add('时间匹配');
              }
            }
          }

          if (matched) {
            final item = MoveItem(
              entity: entity,
              path: path,
              name: name,
              isDirectory: false,
              size: fileSize,
              lastModified: modified,
              matchReason: reasons.join(', '),
            );

            if (rule.targetHash.trim().isNotEmpty) {
              if (shouldAutoDelete) {
                items.add(item);
              } else if (rule.targetHashSize == null ||
                  fileSize == rule.targetHashSize) {
                pendingHashFilterItems.add(item);
              }
            } else {
              if (rule.duplicateFilesOnly) {
                if (shouldAutoDelete) {
                  items.add(item);
                } else {
                  candidateFiles.add(item);
                }
              } else {
                if (reasons.isEmpty) {
                  item.matchReason = '文件对象';
                }
                items.add(item);
              }
            }
          }
        }
      }

      if (pendingHashFilterItems.isNotEmpty) {
        final List<File> filesToHash =
            pendingHashFilterItems.map((item) => item.entity as File).toList();
        final md5Map = await calculateMd5ForFilesParallel(
          filesToHash,
          concurrencyLimit: threads,
          onProgress: (completed, total) {
            final double phaseStart = w1 / totalWeight;
            final double phaseWeight = w2 / totalWeight;
            final double progress =
                phaseStart + (completed / total) * phaseWeight;
            onProgress?.call(progress, '正在校验文件哈希值: $completed/$total');
          },
        );
        final targetHashLower = rule.targetHash.trim().toLowerCase();

        for (var item in pendingHashFilterItems) {
          final hash = md5Map[item.path] ?? '';
          if (hash == targetHashLower) {
            final reasonsList =
                item.matchReason.isEmpty ? [] : item.matchReason.split(', ');
            reasonsList.add('MD5哈希值匹配');
            item.matchReason = reasonsList.join(', ');

            if (rule.duplicateFilesOnly) {
              candidateFiles.add(item);
            } else {
              items.add(item);
            }
          }
        }
      }

      if (rule.duplicateFilesOnly) {
        final Map<int, List<MoveItem>> sizeGroups = {};
        for (var file in candidateFiles) {
          if (file.size > 0) {
            sizeGroups.putIfAbsent(file.size, () => []).add(file);
          }
        }

        final List<MoveItem> filesToQuickHash = [];
        for (var sizeGroup in sizeGroups.values) {
          if (sizeGroup.length > 1) {
            filesToQuickHash.addAll(sizeGroup);
          }
        }

        if (filesToQuickHash.isNotEmpty) {
          final List<File> filesToHash =
              filesToQuickHash.map((item) => item.entity as File).toList();
          final quickHashMap = await calculateQuickHashForFilesParallel(
            filesToHash,
            concurrencyLimit: threads,
            onProgress: (completed, total) {
              final double phaseStart = (w1 + w2) / totalWeight;
              final double phaseWeight = (w3 * 0.4) / totalWeight;
              final double progress =
                  phaseStart + (completed / total) * phaseWeight;
              onProgress?.call(progress, '正在校验重复文件特征码: $completed/$total');
            },
          );

          for (var file in filesToQuickHash) {
            file.quickHash = quickHashMap[file.path] ?? '';
          }
        }

        final Map<String, List<MoveItem>> sizeQuickHashGroups = {};
        for (var file in candidateFiles) {
          if (file.size > 0 &&
              file.quickHash != null &&
              file.quickHash!.isNotEmpty) {
            final key = '${file.size}_${file.quickHash}';
            sizeQuickHashGroups.putIfAbsent(key, () => []).add(file);
          }
        }

        final List<MoveItem> filesToFullHash = [];
        for (var quickHashGroup in sizeQuickHashGroups.values) {
          if (quickHashGroup.length > 1) {
            filesToFullHash.addAll(quickHashGroup);
          }
        }

        if (filesToFullHash.isNotEmpty) {
          final List<File> filesToHash =
              filesToFullHash.map((item) => item.entity as File).toList();
          final md5Map = await calculateMd5ForFilesParallel(
            filesToHash,
            concurrencyLimit: threads,
            onProgress: (completed, total) {
              final double phaseStart = (w1 + w2 + w3 * 0.4) / totalWeight;
              final double phaseWeight = (w3 * 0.6) / totalWeight;
              final double progress =
                  phaseStart + (completed / total) * phaseWeight;
              onProgress?.call(progress, '正在计算重复文件完整哈希: $completed/$total');
            },
          );

          for (var file in filesToFullHash) {
            file.md5Hash = md5Map[file.path] ?? '';
          }
        }

        final Map<String, List<MoveItem>> finalMd5Groups = {};
        for (var file in candidateFiles) {
          if (file.size > 0 &&
              file.md5Hash != null &&
              file.md5Hash!.isNotEmpty) {
            final key = '${file.size}_${file.md5Hash}';
            finalMd5Groups.putIfAbsent(key, () => []).add(file);
          }
        }

        for (var md5Group in finalMd5Groups.values) {
          if (md5Group.length > 1) {
            md5Group.sort((a, b) => a.lastModified.compareTo(b.lastModified));

            final oldest = md5Group.first;
            items.add(MoveItem(
              entity: oldest.entity,
              path: oldest.path,
              name: oldest.name,
              isDirectory: false,
              size: oldest.size,
              lastModified: oldest.lastModified,
              md5Hash: oldest.md5Hash,
              quickHash: oldest.quickHash,
              isSelected: false,
              matchReason: '重复文件 (保留的原始版本)',
            ));

            for (int i = 1; i < md5Group.length; i++) {
              final duplicate = md5Group[i];
              items.add(MoveItem(
                entity: duplicate.entity,
                path: duplicate.path,
                name: duplicate.name,
                isDirectory: false,
                size: duplicate.size,
                lastModified: duplicate.lastModified,
                md5Hash: duplicate.md5Hash,
                quickHash: duplicate.quickHash,
                isSelected: true,
                matchReason: '重复文件 (多余副本)',
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Scan for move error: $e');
    }

    await hashCache.save();

    items.sort((a, b) {
      final aParts = p.split(a.path).length;
      final bParts = p.split(b.path).length;
      return bParts.compareTo(aParts);
    });

    onProgress?.call(1.0, '扫描分析完成');
    return items;
  }

  /// Execute the batch move
  static Future<void> executeMove(
    List<MoveItem> items, {
    required String rootPath,
    required String targetDirPath,
    required MoveFilterRule rule,
    required ConflictStrategy strategy,
    required void Function(int index, double progress, MoveItem item)
        onItemComplete,
    required void Function() onAllComplete,
  }) async {
    if (items.isEmpty) {
      if (rule.flattenToRoot) {
        await _deleteEmptySubfolders(rootPath);
      }
      onAllComplete();
      return;
    }

    final targetRoot =
        rule.flattenToRoot ? Directory(rootPath) : Directory(targetDirPath);
    if (!await targetRoot.exists()) {
      await targetRoot.create(recursive: true);
    }

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (!item.isSelected) {
        onItemComplete(i, (i + 1) / items.length, item);
        continue;
      }

      try {
        if (await item.entity.exists()) {
          final bool shouldAutoDelete = !item.isDirectory &&
              rule.deleteSpecifiedSizeFiles &&
              item.size < rule.deleteSizeLimitBytes;

          if (shouldAutoDelete) {
            await item.entity.delete();
            item.isMoved = true;
          } else {
            String finalTargetPath;
            if (rule.flattenToRoot) {
              finalTargetPath = p.join(rootPath, item.name);
            } else if (rule.keepStructure) {
              final relativePath = p.relative(item.path, from: rootPath);
              finalTargetPath = p.join(targetDirPath, relativePath);
            } else {
              finalTargetPath = p.join(targetDirPath, item.name);
            }

            item.targetPath = finalTargetPath;

            if (item.isDirectory) {
              await _moveDirectory(
                  item.entity as Directory, finalTargetPath, strategy);
            } else {
              await _moveFile(item.entity as File, finalTargetPath, strategy);
            }
            item.isMoved = true;
          }
        } else {
          item.isMoved = false;
          item.error = '源文件不存在';
        }
      } catch (e) {
        item.isMoved = false;
        item.error = e.toString();
      }

      onItemComplete(i, (i + 1) / items.length, item);
    }

    if (rule.flattenToRoot) {
      try {
        await _deleteEmptySubfolders(rootPath);
      } catch (e) {
        debugPrint('Error deleting empty subfolders: $e');
      }
    }

    onAllComplete();
  }

  static Future<void> _deleteEmptySubfolders(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return;

    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is Directory) {
        await _deleteEmptySubfolders(entity.path);
        if (await isDirectoryEmpty(entity)) {
          try {
            await entity.delete();
          } catch (e) {
            debugPrint('Failed to delete empty folder ${entity.path}: $e');
          }
        }
      }
    }
  }

  static Future<void> _moveFile(
      File file, String targetPath, ConflictStrategy strategy) async {
    var finalPath = targetPath;
    final targetFile = File(finalPath);
    if (await targetFile.exists()) {
      switch (strategy) {
        case ConflictStrategy.skip:
          return;
        case ConflictStrategy.overwrite:
          await targetFile.delete();
          break;
        case ConflictStrategy.autoRename:
          finalPath = _getAlternativePath(finalPath);
          break;
      }
    }

    final parentDir = Directory(p.dirname(finalPath));
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    try {
      await file.rename(finalPath);
    } catch (e) {
      await file.copy(finalPath);
      await file.delete();
    }
  }

  static Future<void> _moveDirectory(
      Directory dir, String targetPath, ConflictStrategy strategy) async {
    var finalPath = targetPath;
    final targetDir = Directory(finalPath);
    if (await targetDir.exists()) {
      switch (strategy) {
        case ConflictStrategy.skip:
          return;
        case ConflictStrategy.overwrite:
          await targetDir.delete(recursive: true);
          break;
        case ConflictStrategy.autoRename:
          finalPath = _getAlternativePath(finalPath);
          break;
      }
    }

    final parentDir = Directory(p.dirname(finalPath));
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    try {
      await dir.rename(finalPath);
    } catch (e) {
      await _copyDirectoryRecursively(dir, Directory(finalPath));
      await dir.delete(recursive: true);
    }
  }

  static String _getAlternativePath(String targetPath) {
    final dir = p.dirname(targetPath);
    final ext = p.extension(targetPath);
    final base = p.basenameWithoutExtension(targetPath);

    int counter = 1;
    String alternativePath = targetPath;
    while (true) {
      final newName = '$base ($counter)$ext';
      alternativePath = p.join(dir, newName);
      if (!File(alternativePath).existsSync() &&
          !Directory(alternativePath).existsSync()) {
        break;
      }
      counter++;
    }
    return alternativePath;
  }

  static Future<void> _copyDirectoryRecursively(
      Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity
        in source.list(recursive: false, followLinks: false)) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectoryRecursively(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }
}
