import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'hash_cache_manager.dart';
import 'file_hash_utils.dart';

enum DeleteTarget { file, folder, both }

enum SizeCondition { any, greaterThan, lessThan, equalTo }

enum TimeCondition { any, beforeDate, afterDate, olderThanDays }

class DeleteFilterRule {
  final DeleteTarget target;
  final String extensionFilter; // comma-separated e.g. "mp4, txt"
  final String nameContains;
  final bool caseSensitive;

  // Size Filter
  final SizeCondition sizeCondition;
  final int sizeValueBytes; // converted to bytes

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

  DeleteFilterRule({
    this.target = DeleteTarget.file,
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
  });

  DeleteFilterRule copyWith({
    DeleteTarget? target,
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
  }) {
    return DeleteFilterRule(
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
    );
  }
}

class DeleteItem {
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
  bool isDeleted;
  String? error;

  DeleteItem({
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
    this.isDeleted = false,
    this.error,
  });
}

class DeleteLogic {
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

  /// Scan the folder and apply rules to filter items to be deleted
  static Future<List<DeleteItem>> scanForDelete({
    required String rootPath,
    required DeleteFilterRule rule,
    required bool recursive,
    int? maxThreads,
    void Function(double progress, String status)? onProgress,
  }) async {
    final List<DeleteItem> items = [];
    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      return items;
    }

    // Initialize Hash Cache Manager
    final hashCache = HashCacheManager();
    await hashCache.init();

    // Determine concurrency limit
    int threads = Platform.numberOfProcessors;
    if (rule.maxThreads > 0) {
      threads = rule.maxThreads;
    } else if (maxThreads != null) {
      threads = maxThreads;
    } else {
      // Adaptive thread selection: detect if disk is HDD on Windows
      final isHDD = await isDriveHDD(rootPath);
      if (isHDD) {
        threads =
            1; // Limit to 1 thread for spinning HDD to avoid disk thrashing
      }
    }

    // Process extension filter
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
      final List<FileSystemEntity> entities =
          await dir.list(recursive: recursive, followLinks: false).toList();

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

      // We will perform a first-pass matching for items (files/folders)
      // Special case: duplicate files matching is handled after scanning all files
      List<DeleteItem> candidateFiles = [];
      final List<DeleteItem> pendingHashFilterItems = [];

      for (int i = 0; i < entities.length; i++) {
        final entity = entities[i];

        if (i % 20 == 0 || i == entities.length - 1) {
          final progress = (i / entities.length) * (w1 / totalWeight);
          onProgress?.call(progress, '正在分析文件属性: ${i + 1}/${entities.length}');
        }
        final path = entity.path;
        final name = p.basename(path);

        // Never delete the root directory itself!
        if (p.equals(path, rootPath)) {
          continue;
        }

        final isDir = entity is Directory;

        if (isDir) {
          if (rule.duplicateFilesOnly) {
            // Duplicates filter only applies to files
            continue;
          }
          if (rule.target == DeleteTarget.file) {
            continue;
          }

          // Folder filtering
          bool matched = true;
          List<String> reasons = [];

          // 1. Empty folders only
          final isEmpty = (dirSizeMap[path] ?? 0) == 0 &&
              await isDirectoryEmpty(entity);
          if (rule.emptyFoldersOnly) {
            if (!isEmpty) {
              matched = false;
            } else {
              reasons.add('空文件夹');
            }
          }

          // 2. Name contains
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

          // 3. Size condition
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

          // 4. Time filter (Modified Time)
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

          // If no specific reasons were added but it matched (e.g. no filters set, target == folder/both)
          if (matched && reasons.isEmpty) {
            reasons.add('文件夹对象');
          }

          if (matched) {
            items.add(DeleteItem(
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
          if (rule.target == DeleteTarget.folder) {
            continue;
          }

          // File filtering
          bool matched = true;
          List<String> reasons = [];

          final stat = statMap[path] ?? await entity.stat();
          final fileSize = fileSizeMap[path] ?? stat.size;
          final modified = stat.modified;

          // 1. Empty files only
          if (rule.emptyFilesOnly) {
            if (fileSize > 0) {
              matched = false;
            } else {
              reasons.add('空文件');
            }
          }

          // 2. Extension filter
          if (matched && allowedExtensions.isNotEmpty) {
            final ext = p.extension(path).toLowerCase();
            if (!allowedExtensions.contains(ext)) {
              matched = false;
            } else {
              reasons.add('格式匹配: ${ext.replaceFirst('.', '')}');
            }
          }

          // 3. Name contains
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

          // 4. Size condition
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

          // 5. Time condition
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

          if (matched) {
            final item = DeleteItem(
              entity: entity,
              path: path,
              name: name,
              isDirectory: false,
              size: fileSize,
              lastModified: modified,
              matchReason: reasons.join(', '),
            );

            // 6. Hash filter (MD5) - defer computation and perform in batch parallel
            if (rule.targetHash.trim().isNotEmpty) {
              // Apply Size Pre-filtering optimization: if targetHashSize is specified, only hash files with matching sizes!
              if (rule.targetHashSize == null ||
                  fileSize == rule.targetHashSize) {
                pendingHashFilterItems.add(item);
              }
            } else {
              if (rule.duplicateFilesOnly) {
                candidateFiles.add(item);
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

      // Process deferred hash filtering concurrently using adaptive thread-pool
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

      // Handle duplicate file detection if requested (Three-Stage Filtering)
      if (rule.duplicateFilesOnly) {
        // Stage 1: Group candidate files by size.
        // We only group files with size > 0 (0-byte duplicates are already empty files)
        final Map<int, List<DeleteItem>> sizeGroups = {};
        for (var file in candidateFiles) {
          if (file.size > 0) {
            sizeGroups.putIfAbsent(file.size, () => []).add(file);
          }
        }

        // Stage 2: Calculate Quick Hash (partial contents) for files with size groups > 1
        final List<DeleteItem> filesToQuickHash = [];
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
              final double phaseWeight =
                  (w3 * 0.4) / totalWeight; // 40% of phase 3
              final double progress =
                  phaseStart + (completed / total) * phaseWeight;
              onProgress?.call(progress, '正在校验重复文件特征码: $completed/$total');
            },
          );

          for (var file in filesToQuickHash) {
            file.quickHash = quickHashMap[file.path] ?? '';
          }
        }

        // Group candidate files by size and quick hash
        final Map<String, List<DeleteItem>> sizeQuickHashGroups = {};
        for (var file in candidateFiles) {
          if (file.size > 0 &&
              file.quickHash != null &&
              file.quickHash!.isNotEmpty) {
            final key = '${file.size}_${file.quickHash}';
            sizeQuickHashGroups.putIfAbsent(key, () => []).add(file);
          }
        }

        // Stage 3: Only run full MD5 calculations for candidates with matching sizes AND quick hashes (groups > 1)
        final List<DeleteItem> filesToFullHash = [];
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
              final double phaseWeight =
                  (w3 * 0.6) / totalWeight; // 60% of phase 3
              final double progress =
                  phaseStart + (completed / total) * phaseWeight;
              onProgress?.call(progress, '正在计算重复文件完整哈希: $completed/$total');
            },
          );

          for (var file in filesToFullHash) {
            file.md5Hash = md5Map[file.path] ?? '';
          }
        }

        // Re-group by size and full MD5 hash to detect actual duplicates
        final Map<String, List<DeleteItem>> finalMd5Groups = {};
        for (var file in candidateFiles) {
          if (file.size > 0 &&
              file.md5Hash != null &&
              file.md5Hash!.isNotEmpty) {
            final key = '${file.size}_${file.md5Hash}';
            finalMd5Groups.putIfAbsent(key, () => []).add(file);
          }
        }

        // Sort and select duplicates
        for (var md5Group in finalMd5Groups.values) {
          if (md5Group.length > 1) {
            // Sort by last modified date ascending (oldest first)
            md5Group.sort((a, b) => a.lastModified.compareTo(b.lastModified));

            // Keep the first (oldest) one: set isSelected = false, matchReason = Keep
            final oldest = md5Group.first;
            items.add(DeleteItem(
              entity: oldest.entity,
              path: oldest.path,
              name: oldest.name,
              isDirectory: false,
              size: oldest.size,
              lastModified: oldest.lastModified,
              md5Hash: oldest.md5Hash,
              quickHash: oldest.quickHash,
              isSelected: false, // Do not delete by default
              matchReason: '重复文件 (保留的原始版本)',
            ));

            // Mark the rest as selected for deletion
            for (int i = 1; i < md5Group.length; i++) {
              final duplicate = md5Group[i];
              items.add(DeleteItem(
                entity: duplicate.entity,
                path: duplicate.path,
                name: duplicate.name,
                isDirectory: false,
                size: duplicate.size,
                lastModified: duplicate.lastModified,
                md5Hash: duplicate.md5Hash,
                quickHash: duplicate.quickHash,
                isSelected: true, // Delete by default
                matchReason: '重复文件 (多余副本)',
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Scan for delete error: $e');
    }

    // Save hash cache back to storage
    await hashCache.save();

    // Sort items so folders are deleted AFTER files inside them
    items.sort((a, b) {
      final aParts = p.split(a.path).length;
      final bParts = p.split(b.path).length;
      return bParts.compareTo(aParts); // deeper paths first
    });

    onProgress?.call(1.0, '扫描分析完成');
    return items;
  }

  /// Execute the batch deletion
  static Future<void> executeDelete(
    List<DeleteItem> items, {
    required void Function(int index, double progress, DeleteItem item)
        onItemComplete,
    required void Function() onAllComplete,
  }) async {
    if (items.isEmpty) {
      onAllComplete();
      return;
    }

    // Deletion should be sequential to handle directory-locking issues,
    // and especially since deeper files must be deleted before their parent folders.
    // The items are already sorted by depth descending, so children are deleted before parents.
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (!item.isSelected) {
        onItemComplete(i, (i + 1) / items.length, item);
        continue;
      }

      try {
        if (await item.entity.exists()) {
          if (item.isDirectory) {
            // Delete folder. recursive: true is safer if there are remaining files
            await (item.entity as Directory).delete(recursive: true);
          } else {
            // Delete file
            await (item.entity as File).delete();
          }
          item.isDeleted = true;
        } else {
          item.isDeleted = false;
          item.error = '文件不存在';
        }
      } catch (e) {
        item.isDeleted = false;
        item.error = e.toString();
      }

      onItemComplete(i, (i + 1) / items.length, item);
    }

    onAllComplete();
  }
}
