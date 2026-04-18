import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'music_service.dart';

enum AudioCacheItemStatus { downloaded, skipped, failed }

class AudioCacheProgress {
  final int total;
  final int processed;
  final int downloaded;
  final int skipped;
  final int failed;
  final Song? currentSong;
  final AudioCacheItemStatus? currentStatus;

  const AudioCacheProgress({
    required this.total,
    required this.processed,
    required this.downloaded,
    required this.skipped,
    required this.failed,
    this.currentSong,
    this.currentStatus,
  });

  double get fraction {
    if (total <= 0) {
      return 0;
    }
    return (processed / total).clamp(0.0, 1.0);
  }
}

class OfflineAudioCacheService {
  static final OfflineAudioCacheService _instance =
      OfflineAudioCacheService._internal();
  factory OfflineAudioCacheService() => _instance;
  OfflineAudioCacheService._internal();

  static const String _indexKey = 'offline_audio_cache_index_v1';
  static const int _minValidFileBytes = 16 * 1024;
  static const int _maxCacheBytes = 1024 * 1024 * 1024;
  static const int _pruneTargetBytes = 900 * 1024 * 1024;
  static const int _maxRetriesPerSong = 2;
  static const Duration _betweenSongsDelay = Duration(milliseconds: 120);
  static const Duration _retryBaseDelay = Duration(milliseconds: 700);
  static const Duration _streamChunkTimeout = Duration(seconds: 25);

  final MusicService _musicService = MusicService();
  final http.Client _httpClient = http.Client();
  final Map<String, Future<Map<String, dynamic>>> _inflightDownloads =
      <String, Future<Map<String, dynamic>>>{};

  Future<String?> getCachedFilePathForSong(Song song) async {
    final key = _songKey(song);
    final index = await _readIndex();
    final entry = _entryForKey(index, key);
    if (entry == null) {
      return null;
    }

    final path = (entry['file_path'] ?? '').toString();
    if (path.isEmpty) {
      index.remove(key);
      await _writeIndex(index);
      return null;
    }

    final file = File(path);
    final expectedBytes = _toInt(entry['size_bytes']);
    final valid = await _isHealthyAudioFile(file, expectedBytes: expectedBytes);

    if (!valid) {
      await _deleteFileIfExists(file);
      index.remove(key);
      await _writeIndex(index);
      return null;
    }

    entry['last_accessed_at'] = DateTime.now().toIso8601String();
    index[key] = entry;
    await _writeIndex(index);
    return file.path;
  }

  Future<Map<String, dynamic>> cacheSongIfMissing(Song song) async {
    final existingPath = await getCachedFilePathForSong(song);
    if (existingPath != null) {
      return {
        'success': true,
        'cached': true,
        'downloaded': false,
        'path': existingPath,
      };
    }

    final streamResult = await _musicService.getStreamDataWithHint(
      song.id,
      queryHint: _buildPlaybackQueryHint(song),
      titleHint: song.title,
    );

    if (streamResult['success'] != true) {
      return {
        'success': false,
        'message':
            streamResult['message']?.toString() ?? 'Unable to resolve stream',
      };
    }

    final dynamic rawData = streamResult['data'];
    if (rawData is! Map) {
      return {'success': false, 'message': 'Invalid stream payload'};
    }

    final payload = Map<String, dynamic>.from(rawData);
    final audioUrl = (payload['audio_url']?.toString() ?? '').trim();
    if (audioUrl.isEmpty) {
      return {'success': false, 'message': 'Missing audio URL for download'};
    }

    final rawHeaders = payload['headers'];
    final headers = rawHeaders is Map<String, dynamic>
        ? rawHeaders
        : (rawHeaders is Map ? Map<String, dynamic>.from(rawHeaders) : null);

    return cacheSongFromResolvedData(
      song: song,
      audioUrl: audioUrl,
      headers: headers,
    );
  }

  String cacheKeyForSong(Song song) => _songKey(song);

  Future<Set<String>> getCachedSongKeys(List<Song> songs) async {
    if (songs.isEmpty) {
      return <String>{};
    }

    final index = await _readIndex();
    final cached = <String>{};
    var changed = false;

    for (final song in songs) {
      final key = _songKey(song);
      final entry = _entryForKey(index, key);
      if (entry == null) {
        continue;
      }

      final path = (entry['file_path'] ?? '').toString();
      if (path.isEmpty) {
        index.remove(key);
        changed = true;
        continue;
      }

      final file = File(path);
      final expectedBytes = _toInt(entry['size_bytes']);
      final valid = await _isHealthyAudioFile(
        file,
        expectedBytes: expectedBytes,
      );
      if (!valid) {
        await _deleteFileIfExists(file);
        index.remove(key);
        changed = true;
        continue;
      }

      cached.add(key);
    }

    if (changed) {
      await _writeIndex(index);
    }

    return cached;
  }

  Future<Map<String, dynamic>> cacheSongFromResolvedData({
    required Song song,
    required String audioUrl,
    Map<String, dynamic>? headers,
  }) {
    final key = _songKey(song);
    final active = _inflightDownloads[key];
    if (active != null) {
      return active;
    }

    final future =
        _cacheSongFromResolvedDataInternal(
          song: song,
          audioUrl: audioUrl,
          headers: headers,
        ).whenComplete(() {
          _inflightDownloads.remove(key);
        });

    _inflightDownloads[key] = future;
    return future;
  }

  Future<Map<String, dynamic>> downloadMissingSongs(
    List<Song> songs, {
    void Function(AudioCacheProgress progress)? onProgress,
  }) async {
    final uniqueSongs = <String, Song>{};
    for (final song in songs) {
      uniqueSongs.putIfAbsent(_songKey(song), () => song);
    }

    final total = uniqueSongs.length;
    var downloaded = 0;
    var skipped = 0;
    var failed = 0;
    var downloadedBytes = 0;
    var processed = 0;
    final failures = <String>[];

    onProgress?.call(
      AudioCacheProgress(
        total: total,
        processed: 0,
        downloaded: 0,
        skipped: 0,
        failed: 0,
      ),
    );

    for (final song in uniqueSongs.values) {
      final result = await _cacheSongWithRetries(song);
      final success = result['success'] == true;
      AudioCacheItemStatus itemStatus;

      if (!success) {
        failed++;
        itemStatus = AudioCacheItemStatus.failed;
        final message = result['message']?.toString() ?? 'Unknown error';
        final attempts = _toInt(result['attempts']) ?? 1;
        failures.add('${song.title}: $message (attempts: $attempts)');
      } else if (result['downloaded'] == true) {
        downloaded++;
        itemStatus = AudioCacheItemStatus.downloaded;
        downloadedBytes += _toInt(result['size_bytes']) ?? 0;
      } else {
        skipped++;
        itemStatus = AudioCacheItemStatus.skipped;
      }

      processed++;
      onProgress?.call(
        AudioCacheProgress(
          total: total,
          processed: processed,
          downloaded: downloaded,
          skipped: skipped,
          failed: failed,
          currentSong: song,
          currentStatus: itemStatus,
        ),
      );

      if (processed < total) {
        await Future<void>.delayed(_betweenSongsDelay);
      }
    }

    return {
      'success': failed == 0,
      'downloaded': downloaded,
      'skipped': skipped,
      'failed': failed,
      'downloaded_bytes': downloadedBytes,
      'failures': failures,
    };
  }

  Future<Map<String, dynamic>> _cacheSongFromResolvedDataInternal({
    required Song song,
    required String audioUrl,
    Map<String, dynamic>? headers,
  }) async {
    final trimmedUrl = audioUrl.trim();
    if (trimmedUrl.isEmpty) {
      return {'success': false, 'message': 'audioUrl cannot be empty'};
    }

    final existingPath = await getCachedFilePathForSong(song);
    if (existingPath != null) {
      return {
        'success': true,
        'cached': true,
        'downloaded': false,
        'path': existingPath,
      };
    }

    final key = _songKey(song);
    Map<String, dynamic> index = await _readIndex();
    index = await _pruneIndex(index);
    await _writeIndex(index);

    final cacheDir = await _ensureCacheDirectory();
    final safeFileBase = _safeFileBase(key);
    final tempFile = File(
      '${cacheDir.path}${Platform.pathSeparator}$safeFileBase.part',
    );

    await _deleteFileIfExists(tempFile);

    try {
      final request = http.Request('GET', Uri.parse(trimmedUrl));
      final normalizedHeaders = _normalizeHeaders(headers);
      if (normalizedHeaders != null) {
        request.headers.addAll(normalizedHeaders);
      }

      final response = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 120));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Download failed with status ${response.statusCode}');
      }

      final extension = _inferExtension(trimmedUrl, response.headers);
      final finalFile = File(
        '${cacheDir.path}${Platform.pathSeparator}$safeFileBase$extension',
      );

      var bytesWritten = 0;
      final sink = tempFile.openWrite(mode: FileMode.writeOnly);
      try {
        await for (final chunk in response.stream.timeout(
          _streamChunkTimeout,
          onTimeout: (eventSink) {
            eventSink.addError(
              TimeoutException('Download stream stalled for too long'),
            );
          },
        )) {
          bytesWritten += chunk.length;
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final expectedBytes =
          response.contentLength != null && response.contentLength! > 0
          ? response.contentLength
          : null;

      final valid = await _isHealthyAudioFile(
        tempFile,
        expectedBytes: expectedBytes,
      );
      if (!valid) {
        throw StateError('Downloaded file failed integrity validation');
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(finalFile.path);

      final priorEntry = _entryForKey(index, key);
      if (priorEntry != null) {
        final priorPath = (priorEntry['file_path'] ?? '').toString();
        if (priorPath.isNotEmpty && priorPath != finalFile.path) {
          await _deleteFileIfExists(File(priorPath));
        }
      }

      final now = DateTime.now().toIso8601String();
      final createdAt = priorEntry == null
          ? now
          : (priorEntry['created_at']?.toString() ?? now);

      index[key] = {
        'song_id': song.id,
        'title': song.title,
        'artist': song.artist ?? '',
        'file_path': finalFile.path,
        'size_bytes': bytesWritten,
        'created_at': createdAt,
        'updated_at': now,
        'last_accessed_at': now,
      };

      index = await _pruneIndex(index, protectedKey: key);
      await _writeIndex(index);

      final keptEntry = _entryForKey(index, key);
      if (keptEntry == null) {
        return {
          'success': false,
          'message': 'Storage limit reached while caching audio',
        };
      }

      return {
        'success': true,
        'cached': true,
        'downloaded': true,
        'path': (keptEntry['file_path'] ?? '').toString(),
        'size_bytes': _toInt(keptEntry['size_bytes']) ?? bytesWritten,
      };
    } catch (e) {
      await _deleteFileIfExists(tempFile);
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Directory> _ensureCacheDirectory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}audio_cache_v1',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Map<String, dynamic>> _readIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) {
          return MapEntry(key.toString(), value);
        });
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeIndex(Map<String, dynamic> index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, jsonEncode(index));
  }

  Future<Map<String, dynamic>> _pruneIndex(
    Map<String, dynamic> index, {
    String? protectedKey,
  }) async {
    final normalized = <String, Map<String, dynamic>>{};
    var totalBytes = 0;

    for (final entry in index.entries) {
      final item = _entryForKey(index, entry.key);
      if (item == null) {
        continue;
      }

      final path = (item['file_path'] ?? '').toString();
      if (path.isEmpty) {
        continue;
      }

      final file = File(path);
      final expectedBytes = _toInt(item['size_bytes']);
      final valid = await _isHealthyAudioFile(
        file,
        expectedBytes: expectedBytes,
      );
      if (!valid) {
        await _deleteFileIfExists(file);
        continue;
      }

      final length = await file.length();
      item['size_bytes'] = length;
      normalized[entry.key] = item;
      totalBytes += length;
    }

    if (totalBytes > _maxCacheBytes) {
      final removable =
          normalized.entries
              .where((entry) => entry.key != protectedKey)
              .toList()
            ..sort((a, b) {
              return _entryTimestamp(
                a.value,
              ).compareTo(_entryTimestamp(b.value));
            });

      for (final entry in removable) {
        if (totalBytes <= _pruneTargetBytes) {
          break;
        }

        final path = (entry.value['file_path'] ?? '').toString();
        if (path.isNotEmpty) {
          await _deleteFileIfExists(File(path));
        }

        final size = _toInt(entry.value['size_bytes']) ?? 0;
        totalBytes = max(0, totalBytes - size);
        normalized.remove(entry.key);
      }
    }

    if (totalBytes > _maxCacheBytes &&
        protectedKey != null &&
        normalized.containsKey(protectedKey)) {
      final protectedEntry = normalized[protectedKey]!;
      final path = (protectedEntry['file_path'] ?? '').toString();
      if (path.isNotEmpty) {
        await _deleteFileIfExists(File(path));
      }
      normalized.remove(protectedKey);
    }

    return normalized.map(
      (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
    );
  }

  Future<bool> _isHealthyAudioFile(File file, {int? expectedBytes}) async {
    try {
      if (!await file.exists()) {
        return false;
      }

      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        return false;
      }

      final size = stat.size;
      if (size < _minValidFileBytes) {
        return false;
      }

      if (expectedBytes != null && expectedBytes > 0) {
        final delta = (size - expectedBytes).abs();
        final tolerance = max(2048, (expectedBytes * 0.01).round());
        if (delta > tolerance) {
          return false;
        }
      }

      final raf = await file.open();
      try {
        final sample = await raf.read(96);
        final text = utf8.decode(sample, allowMalformed: true).toLowerCase();
        if (text.contains('<html') ||
            text.contains('<!doctype') ||
            text.contains('<?xml')) {
          return false;
        }
      } finally {
        await raf.close();
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  String _buildPlaybackQueryHint(Song song) {
    final parts = <String>[
      if ((song.artist ?? '').trim().isNotEmpty) (song.artist ?? '').trim(),
      if (song.title.trim().isNotEmpty) song.title.trim(),
    ];

    final hint = parts.join(' ').trim();
    if (hint.isNotEmpty) {
      return hint;
    }

    return song.id.trim();
  }

  String _songKey(Song song) {
    final id = song.id.trim();
    if (id.isNotEmpty) {
      return 'id:$id';
    }

    final title = song.title.trim().toLowerCase();
    final artist = (song.artist ?? '').trim().toLowerCase();
    return 'meta:$title|$artist';
  }

  String _safeFileBase(String songKey) {
    return base64Url.encode(utf8.encode(songKey)).replaceAll('=', '');
  }

  String _inferExtension(String audioUrl, Map<String, String> headers) {
    final contentType = (headers['content-type'] ?? '').toLowerCase();
    if (contentType.contains('audio/mpeg')) {
      return '.mp3';
    }
    if (contentType.contains('audio/mp4') ||
        contentType.contains('audio/aac')) {
      return '.m4a';
    }
    if (contentType.contains('audio/webm')) {
      return '.webm';
    }
    if (contentType.contains('audio/ogg') ||
        contentType.contains('audio/opus')) {
      return '.ogg';
    }
    if (contentType.contains('audio/wav')) {
      return '.wav';
    }

    final uri = Uri.tryParse(audioUrl);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final tail = uri.pathSegments.last.toLowerCase();
      final match = RegExp(
        r'\.(mp3|m4a|aac|webm|ogg|opus|wav)$',
      ).firstMatch(tail);
      if (match != null) {
        return '.${match.group(1)}';
      }
    }

    return '.mp3';
  }

  Map<String, dynamic>? _entryForKey(Map<String, dynamic> index, String key) {
    final raw = index[key];
    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  int _entryTimestamp(Map<String, dynamic> entry) {
    final rawTimestamp =
        (entry['last_accessed_at'] ??
                entry['updated_at'] ??
                entry['created_at'])
            ?.toString();
    if (rawTimestamp == null || rawTimestamp.isEmpty) {
      return 0;
    }

    final dt = DateTime.tryParse(rawTimestamp);
    return dt?.millisecondsSinceEpoch ?? 0;
  }

  int? _toInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  Map<String, String>? _normalizeHeaders(Map<String, dynamic>? rawHeaders) {
    if (rawHeaders == null || rawHeaders.isEmpty) {
      return null;
    }

    final normalized = <String, String>{};
    rawHeaders.forEach((key, value) {
      final k = key.toString().trim();
      final v = value.toString().trim();
      if (k.isNotEmpty && v.isNotEmpty) {
        normalized[k] = v;
      }
    });

    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _deleteFileIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _cacheSongWithRetries(Song song) async {
    Map<String, dynamic> lastResult = <String, dynamic>{
      'success': false,
      'message': 'Unknown caching error',
      'attempts': 0,
    };

    final random = Random();
    for (var attempt = 0; attempt <= _maxRetriesPerSong; attempt++) {
      lastResult = await cacheSongIfMissing(song);
      lastResult['attempts'] = attempt + 1;

      if (lastResult['success'] == true) {
        return lastResult;
      }

      final message = (lastResult['message'] ?? '').toString();
      final canRetry =
          attempt < _maxRetriesPerSong && _isRetriableError(message);
      if (!canRetry) {
        return lastResult;
      }

      final delay = _retryDelayForAttempt(attempt, random);
      await Future<void>.delayed(delay);
    }

    return lastResult;
  }

  Duration _retryDelayForAttempt(int attempt, Random random) {
    final multiplier = 1 << attempt;
    final baseMs = _retryBaseDelay.inMilliseconds * multiplier;
    final jitterMs = random.nextInt(250);
    return Duration(milliseconds: baseMs + jitterMs);
  }

  bool _isRetriableError(String message) {
    final normalized = message.toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    const transientTokens = <String>[
      'timed out',
      'timeout',
      'socket',
      'network',
      'connection',
      'failed host lookup',
      'download stream stalled',
      'unable to resolve stream',
      'stream request failed',
      'request failed',
    ];

    for (final token in transientTokens) {
      if (normalized.contains(token)) {
        return true;
      }
    }

    final statusMatch = RegExp(r'status\s*(\d{3})').firstMatch(normalized);
    if (statusMatch != null) {
      final code = int.tryParse(statusMatch.group(1) ?? '');
      if (code != null) {
        if (code == 403 || code == 408 || code == 425 || code == 429) {
          return true;
        }
        if (code >= 500) {
          return true;
        }
      }
    }

    return false;
  }
}
