import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioCacheService {
  AudioCacheService._internal();
  static final AudioCacheService _instance = AudioCacheService._internal();
  factory AudioCacheService() => _instance;

  static const String _indexKey = 'audio_cache_index_v1';
  static const int _defaultTtlDays = 14;
  static const int _maxCacheBytes = 300 * 1024 * 1024; // 300MB

  final Map<String, Future<void>> _activeDownloads = {};

  Future<Directory> _cacheDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}audio_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Map<String, dynamic>> _readIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _writeIndex(Map<String, dynamic> index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, jsonEncode(index));
  }

  Future<String?> getCachedFilePath(String songId) async {
    final index = await _readIndex();
    final item = index[songId];
    if (item is! Map) return null;

    final map = Map<String, dynamic>.from(item);
    final path = map['path']?.toString();
    final expiresAt = DateTime.tryParse(map['expires_at']?.toString() ?? '');

    if (path == null || path.isEmpty) return null;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      await _removeEntry(songId, map, index: index);
      return null;
    }

    final file = File(path);
    if (!await file.exists()) {
      index.remove(songId);
      await _writeIndex(index);
      return null;
    }

    map['last_accessed_at'] = DateTime.now().toIso8601String();
    index[songId] = map;
    await _writeIndex(index);

    return path;
  }

  Future<void> cacheInBackground(
    String songId,
    String url, {
    Map<String, String>? headers,
  }) async {
    if (_activeDownloads.containsKey(songId)) {
      return _activeDownloads[songId];
    }

    final future = _downloadAndStore(songId, url, headers: headers);
    _activeDownloads[songId] = future;

    try {
      await future;
    } finally {
      _activeDownloads.remove(songId);
    }
  }

  Future<void> _downloadAndStore(
    String songId,
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final dir = await _cacheDir();
      final tempPath = '${dir.path}${Platform.pathSeparator}$songId.part';
      final finalPath = '${dir.path}${Platform.pathSeparator}$songId.bin';

      final req = http.Request('GET', Uri.parse(url));
      if (headers != null && headers.isNotEmpty) {
        req.headers.addAll(headers);
      }
      final resp = await http.Client().send(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return;
      }

      final tempFile = File(tempPath);
      final sink = tempFile.openWrite();
      int totalBytes = 0;

      await for (final chunk in resp.stream) {
        totalBytes += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      final finalFile = File(finalPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(finalPath);

      final index = await _readIndex();
      index[songId] = {
        'path': finalPath,
        'size': totalBytes,
        'url': url,
        'headers': headers,
        'cached_at': DateTime.now().toIso8601String(),
        'last_accessed_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now()
            .add(const Duration(days: _defaultTtlDays))
            .toIso8601String(),
      };
      await _writeIndex(index);
      await _enforceLimits();
    } catch (_) {}
  }

  Future<void> _enforceLimits() async {
    final index = await _readIndex();
    final entries = <MapEntry<String, dynamic>>[];

    int total = 0;
    for (final e in index.entries) {
      if (e.value is Map) {
        entries.add(MapEntry(e.key, Map<String, dynamic>.from(e.value)));
        final size = (e.value['size'] as num?)?.toInt() ?? 0;
        total += size;
      }
    }

    entries.sort((a, b) {
      final at =
          DateTime.tryParse(a.value['last_accessed_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bt =
          DateTime.tryParse(b.value['last_accessed_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return at.compareTo(bt);
    });

    for (final e in entries) {
      if (total <= _maxCacheBytes) break;
      final size = (e.value['size'] as num?)?.toInt() ?? 0;
      await _removeEntry(e.key, e.value, index: index);
      total -= size;
    }
  }

  Future<void> _removeEntry(
    String songId,
    Map<String, dynamic> map, {
    Map<String, dynamic>? index,
  }) async {
    final working = index ?? await _readIndex();
    final path = map['path']?.toString();
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    working.remove(songId);
    await _writeIndex(working);
  }
}
