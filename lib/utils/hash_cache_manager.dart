import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class HashCacheManager {
  static final HashCacheManager _instance = HashCacheManager._internal();
  factory HashCacheManager() => _instance;
  HashCacheManager._internal();

  Map<String, Map<String, dynamic>> _cache = {};
  File? _cacheFile;
  bool _initialized = false;

  /// Initialize the cache by loading hash_cache.json from local app directory.
  /// If [forceReload] is true, reloads from disk even if already initialized.
  Future<void> init({bool forceReload = false}) async {
    if (_initialized && !forceReload) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _cacheFile = File('${dir.path}/hash_cache.json');
      if (await _cacheFile!.exists()) {
        final content = await _cacheFile!.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is Map) {
            _cache = decoded.map((key, value) {
              return MapEntry(
                  key.toString(), Map<String, dynamic>.from(value as Map));
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load hash cache: $e');
    }
    _initialized = true;
  }

  /// Reset initialization flag so next [init()] call reloads from disk.
  void invalidate() {
    _initialized = false;
  }

  /// Get MD5 hash if cache is hit and file stats match
  String? getMd5(String path, int size, int lastModifiedMs) {
    final entry = _cache[path];
    if (entry != null &&
        entry['size'] == size &&
        entry['mtime'] == lastModifiedMs) {
      return entry['md5'] as String?;
    }
    return null;
  }

  /// Get Quick Hash if cache is hit and file stats match
  String? getQuickHash(String path, int size, int lastModifiedMs) {
    final entry = _cache[path];
    if (entry != null &&
        entry['size'] == size &&
        entry['mtime'] == lastModifiedMs) {
      return entry['quickHash'] as String?;
    }
    return null;
  }

  /// Set cache values
  void set(String path, int size, int lastModifiedMs,
      {String? md5, String? quickHash}) {
    final entry = _cache[path] ?? {};
    entry['size'] = size;
    entry['mtime'] = lastModifiedMs;
    if (md5 != null) entry['md5'] = md5;
    if (quickHash != null) entry['quickHash'] = quickHash;
    _cache[path] = entry;
  }

  /// Save cache to disk, keeping cache size in check (maximum 30000 entries)
  Future<void> save() async {
    if (_cacheFile == null) return;
    try {
      if (_cache.length > 30000) {
        final keys = _cache.keys.toList();
        // Remove older half of the cache entries to avoid large files
        for (int i = 0; i < keys.length - 15000; i++) {
          _cache.remove(keys[i]);
        }
      }
      final jsonStr = jsonEncode(_cache);
      await _cacheFile!.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('Failed to save hash cache: $e');
    }
  }
}
