import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'hash_cache_manager.dart';

/// Internal sink to collect the digest result from chunked MD5 calculation.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// Shared utility for file hash computation and related disk operations.
/// Replaces duplicated code in delete_logic.dart and move_logic.dart.
class FileHashUtils {
  /// Calculate full MD5 of a file with guaranteed handle release.
  /// This is a top-level function (not a closure) so it can be sent to an isolate via [compute].
  static Future<String> computeFileMd5(String path) async {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      if (!file.existsSync()) return '';
      raf = await file.open(mode: FileMode.read);
      final output = _DigestSink();
      final input = md5.startChunkedConversion(output);
      const bufferSize = 64 * 1024;
      while (true) {
        final bytes = await raf.read(bufferSize);
        if (bytes.isEmpty) break;
        input.add(bytes);
      }
      input.close();
      return output.value?.toString() ?? '';
    } catch (e) {
      return '';
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  /// Calculate quick hash (MD5 of first/last 8KB) of a file.
  /// This is a top-level function so it can be sent to an isolate via [compute].
  static Future<String> computeFileQuickHash(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return '';
      final size = await file.length();
      final raf = await file.open(mode: FileMode.read);

      final int headerSize = size > 8192 ? 8192 : size;
      final headerBytes = await raf.read(headerSize);

      List<int> footerBytes = [];
      if (size > 8192) {
        await raf.setPosition(size - 8192);
        footerBytes = await raf.read(8192);
      }
      await raf.close();

      final combined = [...headerBytes, ...footerBytes];
      final hash = md5.convert(combined);
      return hash.toString();
    } catch (e) {
      return '';
    }
  }

  /// Calculate MD5 of a single file using Flutter's [compute] (background isolate).
  static Future<String> calculateFileMd5(File file) async {
    try {
      return await compute(computeFileMd5, file.path);
    } catch (e) {
      debugPrint('Error computing MD5 for ${file.path}: $e');
      return '';
    }
  }

  /// Calculate Quick Hash of a single file using Flutter's [compute].
  static Future<String> calculateFileQuickHash(File file) async {
    try {
      return await compute(computeFileQuickHash, file.path);
    } catch (e) {
      debugPrint('Error computing quick hash for ${file.path}: $e');
      return '';
    }
  }

  /// Parallel MD5 computation with configurable concurrency limit and progress callback.
  static Future<Map<String, String>> calculateMd5ForFilesParallel(
    List<File> files, {
    int? concurrencyLimit,
    void Function(int completed, int total)? onProgress,
  }) async {
    return _calculateHashesParallel(
      files,
      hashFn: computeFileMd5,
      cacheKey: 'md5',
      concurrencyLimit: concurrencyLimit,
      onProgress: onProgress,
      cacheSetter: (cache, path, size, mtime, hash) =>
          cache.set(path, size, mtime, md5: hash),
      cacheGetter: (cache, path, size, mtime) =>
          cache.getMd5(path, size, mtime),
    );
  }

  /// Parallel Quick Hash computation with configurable concurrency limit and progress callback.
  static Future<Map<String, String>> calculateQuickHashForFilesParallel(
    List<File> files, {
    int? concurrencyLimit,
    void Function(int completed, int total)? onProgress,
  }) async {
    return _calculateHashesParallel(
      files,
      hashFn: computeFileQuickHash,
      cacheKey: 'quickHash',
      concurrencyLimit: concurrencyLimit,
      onProgress: onProgress,
      cacheSetter: (cache, path, size, mtime, hash) =>
          cache.set(path, size, mtime, quickHash: hash),
      cacheGetter: (cache, path, size, mtime) =>
          cache.getQuickHash(path, size, mtime),
    );
  }

  static final Map<String, bool> _hddCache = {};

  /// Generic parallel hash computation engine.
  static Future<Map<String, String>> _calculateHashesParallel(
    List<File> files, {
    required Future<String> Function(String path) hashFn,
    required String cacheKey,
    int? concurrencyLimit,
    void Function(int completed, int total)? onProgress,
    required void Function(HashCacheManager cache, String path, int size,
            int mtime, String hash)
        cacheSetter,
    required String? Function(
            HashCacheManager cache, String path, int size, int mtime)
        cacheGetter,
  }) async {
    final Map<String, String> results = {};
    if (files.isEmpty) return results;

    final cache = HashCacheManager();
    await cache.init();
    final List<File> needCompute = [];
    final Map<String, int> fileSizes = {};
    final Map<String, int> fileMtimes = {};

    // Check cache first
    for (var file in files) {
      try {
        final path = file.path;
        final size = await file.length();
        final stat = await file.stat();
        final mtime = stat.modified.millisecondsSinceEpoch;
        fileSizes[path] = size;
        fileMtimes[path] = mtime;

        final cached = cacheGetter(cache, path, size, mtime);
        if (cached != null && cached.isNotEmpty) {
          results[path] = cached;
        } else {
          needCompute.add(file);
        }
      } catch (e) {
        results[file.path] = '';
      }
    }

    int completedCount = files.length - needCompute.length;
    onProgress?.call(completedCount, files.length);

    if (needCompute.isEmpty) {
      return results;
    }

    final int maxConcurrency = concurrencyLimit ?? Platform.numberOfProcessors;
    final completer = Completer<Map<String, String>>();
    int activeCount = 0;
    int taskIndex = 0;

    void runNext() async {
      if (taskIndex >= needCompute.length) {
        if (activeCount == 0 && !completer.isCompleted) {
          completer.complete(results);
        }
        return;
      }

      final file = needCompute[taskIndex++];
      activeCount++;

      try {
        final path = file.path;
        final hash = await compute(hashFn, path);
        results[path] = hash;

        final size = fileSizes[path] ?? await file.length();
        final mtime = fileMtimes[path] ??
            (await file.stat()).modified.millisecondsSinceEpoch;
        cacheSetter(cache, path, size, mtime, hash);
      } catch (e) {
        debugPrint('Error in parallel hash calculation: $e');
        results[file.path] = '';
      } finally {
        activeCount--;
        completedCount++;
        onProgress?.call(completedCount, files.length);
        runNext();
      }
    }

    final initialBatch = maxConcurrency < needCompute.length
        ? maxConcurrency
        : needCompute.length;
    for (int i = 0; i < initialBatch; i++) {
      runNext();
    }

    return completer.future;
  }

  // ─── Disk Utility Methods ─────────────────────────────────────────────────

  /// Detect if target path resides on a spinning Hard Disk Drive (HDD) on Windows.
  static Future<bool> isDriveHDD(String path) async {
    if (!Platform.isWindows) return false;
    String driveLetter = 'C';
    if (path.length >= 2 && path[1] == ':') {
      driveLetter = path[0].toUpperCase();
    }
    if (_hddCache.containsKey(driveLetter)) {
      return _hddCache[driveLetter]!;
    }
    try {
      final result = await Process.run('powershell', [
        '-Command',
        'Get-PhysicalDisk | Where-Object { \$_.DeviceID -eq (Get-Partition -DriveLetter $driveLetter | Get-Disk).Number } | Select-Object -ExpandProperty MediaType',
      ]);
      if (result.exitCode == 0) {
        final out = result.stdout.toString().trim().toUpperCase();
        final isHDD = out.contains('HDD');
        _hddCache[driveLetter] = isHDD;
        return isHDD;
      }
    } catch (e) {
      debugPrint('Failed to detect disk type: $e');
    }
    _hddCache[driveLetter] = false;
    return false;
  }

  /// Check if a directory is empty.
  static Future<bool> isDirectoryEmpty(Directory dir) async {
    try {
      final list =
          await dir.list(recursive: false, followLinks: false).take(1).toList();
      return list.isEmpty;
    } catch (e) {
      return true;
    }
  }

  /// Get the total size of a directory recursively.
  static Future<int> getDirectorySize(Directory dir) async {
    int totalSize = 0;
    try {
      if (await dir.exists()) {
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } catch (e) {
      // Ignore reading errors on nested items
    }
    return totalSize;
  }

  /// Format bytes into a human-readable string (for match reasons).
  static String formatSizeForReason(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Parse extension filter string into list of normalized extensions (e.g. ".mp4", ".txt").
  static List<String> parseExtensionFilter(String filter) {
    if (filter.trim().isEmpty || filter.trim() == '*') return [];
    return filter
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

  /// Determine optimal thread count based on rule settings and disk type.
  static Future<int> determineThreadCount({
    required String rootPath,
    int ruleMaxThreads = 0,
    int? callerMaxThreads,
  }) async {
    int threads = Platform.numberOfProcessors;
    if (ruleMaxThreads > 0) {
      threads = ruleMaxThreads;
    } else if (callerMaxThreads != null) {
      threads = callerMaxThreads;
    } else {
      final isHDD = await isDriveHDD(rootPath);
      if (isHDD) {
        threads = 1;
      }
    }
    return threads;
  }
}
