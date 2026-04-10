import 'dart:async';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/music_service.dart';
import '../services/offline_audio_cache_service.dart';
import '../services/offline_library_service.dart';
import '../services/user_activity_service.dart';
import '../widgets/song_tile.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;
  final void Function(Song, [List<Song>?]) onSongSelected;
  final Future<bool> Function(Song, [List<Song>?]) onAddToQueue;
  final ValueChanged<bool> onBack;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.onSongSelected,
    required this.onAddToQueue,
    required this.onBack,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final MusicService _musicService = MusicService();
  final OfflineLibraryService _offlineLibrary = OfflineLibraryService();
  final OfflineAudioCacheService _audioCache = OfflineAudioCacheService();
  final UserActivityService _activity = UserActivityService();

  Map<String, dynamic>? _playlist;
  List<Song> _songs = [];
  Set<String> _cachedSongKeys = <String>{};
  bool _isLoading = true;
  bool _isDownloadInProgress = false;
  int _downloadProcessed = 0;
  int _downloadTotal = 0;
  int _downloadedCount = 0;
  int _skippedCount = 0;
  int _failedCount = 0;
  String? _downloadCurrentTitle;

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    setState(() => _isLoading = true);
    Map<String, dynamic>? playlist = await _musicService.getPlaylist(
      widget.playlistId,
    );

    playlist ??= await _offlineLibrary.getCachedPlaylist(widget.playlistId);

    if (!mounted) return;
    if (playlist == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not load playlist'),
          backgroundColor: Colors.red[700],
        ),
      );
      return;
    }

    final rawSongs = playlist['songs'] as List<dynamic>? ?? [];
    final songs = rawSongs
        .whereType<Map>()
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    setState(() {
      _playlist = playlist;
      _songs = songs;
      _cachedSongKeys = <String>{};
      _isLoading = false;
    });

    unawaited(_refreshCachedIndicators(songs));
  }

  Future<void> _refreshCachedIndicators([List<Song>? songs]) async {
    final targetSongs = songs ?? _songs;
    if (targetSongs.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cachedSongKeys = <String>{};
      });
      return;
    }

    final keys = await _audioCache.getCachedSongKeys(targetSongs);
    if (!mounted) {
      return;
    }

    setState(() {
      _cachedSongKeys = keys;
    });
  }

  Future<void> _downloadPlaylistLibrary() async {
    if (_songs.isEmpty || _isDownloadInProgress) {
      return;
    }

    setState(() {
      _isDownloadInProgress = true;
      _downloadProcessed = 0;
      _downloadTotal = _songs.length;
      _downloadedCount = 0;
      _skippedCount = 0;
      _failedCount = 0;
      _downloadCurrentTitle = null;
    });

    final playlistName = (_playlist?['name'] ?? 'Playlist').toString();
    try {
      await _offlineLibrary.cachePlaylist(
        widget.playlistId,
        playlistName,
        _songs,
      );

      final result = await _audioCache.downloadMissingSongs(
        _songs,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }

          setState(() {
            _downloadProcessed = progress.processed;
            _downloadTotal = progress.total;
            _downloadedCount = progress.downloaded;
            _skippedCount = progress.skipped;
            _failedCount = progress.failed;
            _downloadCurrentTitle = progress.currentSong?.title;

            final currentSong = progress.currentSong;
            final currentStatus = progress.currentStatus;
            if (currentSong != null &&
                (currentStatus == AudioCacheItemStatus.downloaded ||
                    currentStatus == AudioCacheItemStatus.skipped)) {
              _cachedSongKeys.add(_audioCache.cacheKeyForSong(currentSong));
            }
          });
        },
      );
      if (!mounted) {
        return;
      }

      final downloaded = _toInt(result['downloaded']);
      final skipped = _toInt(result['skipped']);
      final failed = _toInt(result['failed']);
      final downloadedBytes = _toInt(result['downloaded_bytes']);
      final downloadedMb = downloadedBytes / (1024 * 1024);

      final message = failed > 0
          ? 'Downloaded $downloaded, already cached $skipped, failed $failed.'
          : 'Playlist ready offline: $downloaded downloaded, $skipped cached (${downloadedMb.toStringAsFixed(1)} MB).';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: failed > 0 ? Colors.orange[700] : Colors.green[700],
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playlist download failed: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadInProgress = false;
          _downloadCurrentTitle = null;
        });
      }
      unawaited(_refreshCachedIndicators());
    }
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isSongCached(Song song) {
    return _cachedSongKeys.contains(_audioCache.cacheKeyForSong(song));
  }

  void _playSongs({required bool shuffle}) {
    if (_songs.isEmpty) {
      return;
    }

    final queue = List<Song>.from(_songs);
    if (shuffle && queue.length > 1) {
      queue.shuffle();
    }
    widget.onSongSelected(queue.first, queue);
  }

  Widget _buildPlaylistSummaryCard() {
    final name = (_playlist?['name'] ?? 'Playlist').toString();
    final cachedCount = _songs.where(_isSongCached).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F315F), Color(0xFF142647), Color(0xFF1A1A1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${_songs.length} songs  •  $cachedCount offline',
            style: TextStyle(color: Colors.grey[300], fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _songs.isEmpty
                      ? null
                      : () => _playSongs(shuffle: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Play all'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _songs.isEmpty
                      ? null
                      : () => _playSongs(shuffle: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0B3B8C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('Shuffle'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadProgressHeader() {
    final total = _downloadTotal <= 0 ? 1 : _downloadTotal;
    final fraction = (_downloadProcessed / total).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Caching songs... $_downloadProcessed/$_downloadTotal',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if ((_downloadCurrentTitle ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _downloadCurrentTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: fraction,
            minHeight: 5,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0B3B8C)),
          ),
          const SizedBox(height: 8),
          Text(
            'Downloaded $_downloadedCount  •  Cached $_skippedCount  •  Failed $_failedCount',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _renamePlaylist() async {
    if (_playlist == null) return;

    final controller = TextEditingController(
      text: (_playlist!['name'] ?? '').toString(),
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Rename Playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: TextStyle(color: Colors.grey[500]),
              filled: true,
              fillColor: const Color(0xFF3A3A3A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text(
                'Save',
                style: TextStyle(color: Color(0xFF0B3B8C)),
              ),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty || _playlist == null) return;

    final result = await _musicService.renamePlaylist(
      widget.playlistId,
      newName,
    );
    if (!mounted) return;

    if (result['success'] == true) {
      await _loadPlaylist();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Playlist renamed'),
          backgroundColor: Colors.green[700],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Could not rename playlist',
          ),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  Future<void> _deletePlaylist() async {
    if (_playlist == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Delete Playlist'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final result = await _musicService.deletePlaylist(widget.playlistId);
    if (!mounted) return;

    if (result['success'] == true) {
      widget.onBack(true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['message']?.toString() ?? 'Could not delete playlist',
        ),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  Future<void> _removeSong(Song song) async {
    final result = await _musicService.removeSongFromPlaylist(
      widget.playlistId,
      song.id,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      await _loadPlaylist();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message']?.toString() ?? 'Could not remove song'),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  Future<void> _confirmAndRemoveSong(Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Remove Song'),
          content: Text(
            'Remove "${song.title}" from this playlist?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Remove',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _removeSong(song);
    }
  }

  Future<void> _showAddSongsSheet() async {
    final parentContext = context;
    final likedSongs = await _musicService.getLikedSongs();
    final searchController = TextEditingController();
    List<Song> searchResults = [];
    bool isSearching = false;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Add Songs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search songs to add',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.grey[400],
                        ),
                        filled: true,
                        fillColor: const Color(0xFF282828),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (query) async {
                        setSheetState(() {
                          isSearching = true;
                        });
                        final results = await _musicService.searchSongs(query);
                        setSheetState(() {
                          searchResults = results;
                          isSearching = false;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    if (isSearching)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          color: Color(0xFF0B3B8C),
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        children: [
                          if (searchResults.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Search Results',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            ...searchResults.map(
                              (song) => ListTile(
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  song.artist ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                                trailing: const Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: Color(0xFF0B3B8C),
                                ),
                                onTap: () async {
                                  final navigator = Navigator.of(parentContext);
                                  final messenger = ScaffoldMessenger.of(
                                    parentContext,
                                  );
                                  final res = await _musicService
                                      .addSongToPlaylist(
                                        widget.playlistId,
                                        song,
                                      );
                                  if (!mounted) return;
                                  if (res['success'] == true) {
                                    navigator.pop();
                                    await _loadPlaylist();
                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: const Text('Song added'),
                                        backgroundColor: Colors.green[700],
                                      ),
                                    );
                                  } else {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          res['message']?.toString() ??
                                              'Could not add song',
                                        ),
                                        backgroundColor: Colors.red[700],
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Liked Songs',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (likedSongs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                'No liked songs yet',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          else
                            ...likedSongs.map(
                              (song) => ListTile(
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  song.artist ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                                trailing: const Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: Color(0xFF0B3B8C),
                                ),
                                onTap: () async {
                                  final navigator = Navigator.of(parentContext);
                                  final messenger = ScaffoldMessenger.of(
                                    parentContext,
                                  );
                                  final res = await _musicService
                                      .addSongToPlaylist(
                                        widget.playlistId,
                                        song,
                                      );
                                  if (!mounted) return;
                                  if (res['success'] == true) {
                                    navigator.pop();
                                    await _loadPlaylist();
                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: const Text('Song added'),
                                        backgroundColor: Colors.green[700],
                                      ),
                                    );
                                  } else {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          res['message']?.toString() ??
                                              'Could not add song',
                                        ),
                                        backgroundColor: Colors.red[700],
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (_playlist?['name'] ?? 'Playlist').toString();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => widget.onBack(false),
        ),
        title: Text(name),
        actions: [
          IconButton(
            icon: _isDownloadInProgress
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            tooltip: _isDownloadInProgress
                ? 'Downloading audio...'
                : 'Download audio',
            onPressed: _songs.isEmpty || _isDownloadInProgress
                ? null
                : _downloadPlaylistLibrary,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') {
                _renamePlaylist();
              } else if (value == 'delete') {
                _deletePlaylist();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSongsSheet,
        backgroundColor: const Color(0xFF0B3B8C),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Songs'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0B3B8C)),
            )
          : _songs.isEmpty
          ? Center(
              child: Text(
                'No songs in this playlist yet',
                style: TextStyle(color: Colors.grey[400], fontSize: 16),
              ),
            )
          : Column(
              children: [
                if (_isDownloadInProgress) _buildDownloadProgressHeader(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadPlaylist,
                    color: const Color(0xFF0B3B8C),
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: _songs.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _buildPlaylistSummaryCard();
                        }

                        final song = _songs[index - 1];
                        final isCached = _isSongCached(song);

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Dismissible(
                            key: ValueKey('${song.id}-${index.toString()}'),
                            background: Container(
                              decoration: BoxDecoration(
                                color: Colors.red[700],
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: const Icon(
                                Icons.delete_rounded,
                                color: Colors.white,
                              ),
                            ),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) async {
                              await _removeSong(song);
                              return false;
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1D1D1D),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 2,
                                ),
                                title: SongTile(
                                  song: song,
                                  onTap: () async {
                                    await _activity.recordPlaylistPlay(
                                      playlistId: widget.playlistId,
                                      playlistName:
                                          (_playlist?['name'] ?? 'Playlist')
                                              .toString(),
                                      coverUrl: song.coverUrl,
                                    );
                                    widget.onSongSelected(song, _songs);
                                  },
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isCached)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(
                                          Icons.download_done_rounded,
                                          size: 16,
                                          color: Color(0xFF0B3B8C),
                                        ),
                                      ),
                                    PopupMenuButton<String>(
                                      onSelected: (value) async {
                                        if (value == 'add_to_queue') {
                                          final messenger =
                                              ScaffoldMessenger.of(context);
                                          final added =
                                              await widget.onAddToQueue(
                                                song,
                                                _songs,
                                              );
                                          if (!mounted) return;
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                added
                                                    ? 'Added to queue'
                                                    : 'Song is already in queue',
                                              ),
                                              backgroundColor: added
                                                  ? Colors.green[700]
                                                  : Colors.orange[700],
                                            ),
                                          );
                                        } else if (value == 'remove') {
                                          await _confirmAndRemoveSong(song);
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'add_to_queue',
                                          child: Text('Add to queue'),
                                        ),
                                        PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Remove from playlist'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
