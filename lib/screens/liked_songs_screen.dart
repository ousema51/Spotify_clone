import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/music_service.dart';
import '../services/network_status_service.dart';
import '../services/offline_audio_cache_service.dart';
import '../services/offline_library_service.dart';
import '../widgets/song_tile.dart';

class LikedSongsScreen extends StatefulWidget {
  final void Function(Song, [List<Song>?]) onSongSelected;
  final Future<bool> Function(Song, [List<Song>?]) onAddToQueue;
  final VoidCallback onBack;

  const LikedSongsScreen({
    super.key,
    required this.onSongSelected,
    required this.onAddToQueue,
    required this.onBack,
  });

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  final MusicService _musicService = MusicService();
  final OfflineLibraryService _offlineLibrary = OfflineLibraryService();
  final OfflineAudioCacheService _audioCache = OfflineAudioCacheService();
  final NetworkStatusService _networkStatus = NetworkStatusService();
  bool _isLoading = true;
  bool _isDownloadInProgress = false;
  bool _isOfflineMode = false;
  List<Song> _likedSongs = [];
  Set<String> _cachedSongKeys = <String>{};
  List<Map<String, dynamic>> _playlists = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final cachedLiked = await _offlineLibrary.getCachedLikedSongs();
    final cachedPlaylists = await _offlineLibrary.getCachedPlaylists();
    final cachedSongKeys = await _audioCache.getCachedSongKeys(cachedLiked);

    if (mounted) {
      setState(() {
        _likedSongs = cachedLiked;
        _playlists = cachedPlaylists;
        _cachedSongKeys = cachedSongKeys;
      });
    }

    final isOnline = await _networkStatus.isOnline();
    if (!isOnline) {
      if (!mounted) return;
      setState(() {
        _isOfflineMode = true;
        _isLoading = false;
      });
      return;
    }

    try {
      final likedSongs = await _musicService.getLikedSongs();
      final playlists = await _musicService.getMyPlaylists();
      final onlineCachedSongKeys = await _audioCache.getCachedSongKeys(likedSongs);
      await _offlineLibrary.cacheLikedSongs(likedSongs);
      await _offlineLibrary.cachePlaylists(playlists);

      if (!mounted) return;
      setState(() {
        _likedSongs = likedSongs;
        _cachedSongKeys = onlineCachedSongKeys;
        _playlists = playlists;
        _isOfflineMode = false;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isOfflineMode = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadLibrary() async {
    if (_likedSongs.isEmpty || _isDownloadInProgress) {
      return;
    }

    final isOnline = await _networkStatus.isOnline();
    if (!isOnline) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Reconnect to download audio for offline playback.'),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    setState(() {
      _isDownloadInProgress = true;
    });

    try {
      await _offlineLibrary.cacheLikedSongs(_likedSongs);
      final result = await _audioCache.downloadMissingSongs(_likedSongs);
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
          : 'Offline ready: $downloaded downloaded, $skipped cached (${downloadedMb.toStringAsFixed(1)} MB).';

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
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      final refreshedKeys = await _audioCache.getCachedSongKeys(_likedSongs);
      if (mounted) {
        setState(() {
          _isDownloadInProgress = false;
          _cachedSongKeys = refreshedKeys;
        });
      }
    }
  }

  bool _isSongCached(Song song) {
    return _cachedSongKeys.contains(_audioCache.cacheKeyForSong(song));
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

  void _playLikedSongs({required bool shuffle}) {
    if (_likedSongs.isEmpty) {
      return;
    }

    final queue = List<Song>.from(_likedSongs);
    if (shuffle && queue.length > 1) {
      queue.shuffle();
    }
    widget.onSongSelected(queue.first, queue);
  }

  Widget _buildStatChip({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: Colors.grey[300], fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    final cachedCount = _likedSongs.where(_isSongCached).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF13336E), Color(0xFF0F2146), Color(0xFF151515)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Liked Songs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your saved songs in one place',
                      style: TextStyle(color: Colors.grey[300], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatChip(
                  label: 'Total songs',
                  value: _likedSongs.length.toString(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatChip(
                  label: 'Offline cached',
                  value: cachedCount.toString(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _likedSongs.isEmpty
                      ? null
                      : () => _playLikedSongs(shuffle: false),
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
                  onPressed: _likedSongs.isEmpty
                      ? null
                      : () => _playLikedSongs(shuffle: true),
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

  Future<void> _unlikeSong(Song song) async {
    final songId = song.id.trim();
    if (songId.isEmpty) {
      return;
    }

    final isOnline = await _networkStatus.isOnline();
    if (!isOnline) {
      await _offlineLibrary.removeLikedSongLocally(songId);
      await _offlineLibrary.queueLikeAction(songId: songId, like: false);
      if (!mounted) return;
      setState(() {
        _likedSongs.removeWhere((s) => s.id == songId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Removed locally. Will sync when you reconnect.'),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    final result = await _musicService.unlikeSong(songId);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _likedSongs.removeWhere((s) => s.id == songId);
      });
      await _offlineLibrary.cacheLikedSongs(_likedSongs);
    } else if (_looksLikeConnectivityError(result['message']?.toString())) {
      await _offlineLibrary.removeLikedSongLocally(songId);
      await _offlineLibrary.queueLikeAction(songId: songId, like: false);
      if (!mounted) return;
      setState(() {
        _likedSongs.removeWhere((s) => s.id == songId);
        _isOfflineMode = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Offline now. Change queued for sync.'),
          backgroundColor: Colors.orange[700],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Could not unlike song',
          ),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  bool _looksLikeConnectivityError(String? message) {
    final text = (message ?? '').toLowerCase();
    return text.contains('socket') ||
        text.contains('network') ||
        text.contains('timed out') ||
        text.contains('failed host lookup') ||
        text.contains('connection');
  }

  int _playlistSongCount(Map<String, dynamic> playlist) {
    final songs = playlist['songs'];
    return songs is List ? songs.length : 0;
  }

  Future<void> _showChoosePlaylistForSong(Song song) async {
    if (_playlists.isEmpty) {
      _playlists = await _offlineLibrary.getCachedPlaylists();
      if (mounted) {
        setState(() {});
      }

      if (_playlists.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Create a playlist first in Library'),
            backgroundColor: Colors.orange[700],
          ),
        );
        return;
      }
    }

    if (!mounted) return;

    final parentContext = context;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _playlists.length,
            itemBuilder: (context, index) {
              final playlist = _playlists[index];
              final playlistName = (playlist['name'] ?? 'Untitled Playlist')
                  .toString();
              final playlistId = (playlist['_id'] ?? '').toString();

              return ListTile(
                leading: const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white70,
                ),
                title: Text(playlistName),
                subtitle: Text(
                  '${_playlistSongCount(playlist)} songs',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                onTap: () async {
                  final navigator = Navigator.of(parentContext);
                  final messenger = ScaffoldMessenger.of(parentContext);

                  final isOnline = await _networkStatus.isOnline();
                  if (!isOnline) {
                    if (!mounted) return;
                    navigator.pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Reconnect to add songs to playlists.',
                        ),
                        backgroundColor: Colors.orange[700],
                      ),
                    );
                    return;
                  }

                  final result = await _musicService.addSongToPlaylist(
                    playlistId,
                    song,
                  );

                  if (!mounted) return;
                  navigator.pop();
                  if (result['success'] == true) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Added to $playlistName'),
                        backgroundColor: Colors.green[700],
                      ),
                    );
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          result['message']?.toString() ??
                              'Could not add to playlist',
                        ),
                        backgroundColor: Colors.red[700],
                      ),
                    );
                  }
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: const Text('Liked Songs'),
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
            onPressed: _likedSongs.isEmpty || _isDownloadInProgress
                ? null
                : _downloadLibrary,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0B3B8C)),
            )
          : _likedSongs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border_rounded,
                    color: Colors.grey[600],
                    size: 58,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No liked songs yet',
                    style: TextStyle(color: Colors.grey[300], fontSize: 16),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFF0B3B8C),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: _likedSongs.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      children: [
                        if (_isOfflineMode)
                          Container(
                            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2112),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF8A6A35)),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.wifi_off_rounded,
                                  color: Color(0xFFF6C977),
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Offline mode: showing cached liked songs.',
                                    style: TextStyle(
                                      color: Color(0xFFF6C977),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        _buildOverviewCard(),
                      ],
                    );
                  }

                  final song = _likedSongs[index - 1];
                  final isCached = _isSongCached(song);

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
                          onTap: () => widget.onSongSelected(song, _likedSongs),
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
                                if (value == 'add_to_playlist') {
                                  _showChoosePlaylistForSong(song);
                                } else if (value == 'add_to_queue') {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final added = await widget.onAddToQueue(
                                    song,
                                    _likedSongs,
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
                                } else if (value == 'remove_liked') {
                                  _unlikeSong(song);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'add_to_playlist',
                                  child: Text('Add to playlist'),
                                ),
                                PopupMenuItem(
                                  value: 'add_to_queue',
                                  child: Text('Add to queue'),
                                ),
                                PopupMenuItem(
                                  value: 'remove_liked',
                                  child: Text('Remove from liked songs'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
