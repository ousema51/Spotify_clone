import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/network_status_service.dart';
import '../services/offline_audio_cache_service.dart';
import '../services/offline_library_service.dart';
import '../services/music_service.dart';
import '../services/auth_service.dart';

class LibraryScreen extends StatefulWidget {
  final void Function(Song, [List<Song>?]) onSongSelected;
  final ValueChanged<String> onOpenPlaylist;
  final VoidCallback onOpenLikedSongs;

  const LibraryScreen({
    super.key,
    required this.onSongSelected,
    required this.onOpenPlaylist,
    required this.onOpenLikedSongs,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final MusicService _musicService = MusicService();
  final AuthService _authService = AuthService();
  final OfflineLibraryService _offlineLibrary = OfflineLibraryService();
  final OfflineAudioCacheService _audioCache = OfflineAudioCacheService();
  final NetworkStatusService _networkStatus = NetworkStatusService();
  List<Song> _likedSongs = [];
  List<Map<String, dynamic>> _playlists = [];
  final Set<String> _playlistDownloadsInProgress = <String>{};
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _isOfflineMode = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _isLoggedIn = await _authService.isLoggedIn();

    if (_isLoggedIn) {
      final cachedLikedSongs = await _offlineLibrary.getCachedLikedSongs();
      final cachedPlaylists = await _offlineLibrary.getCachedPlaylists();

      if (mounted) {
        setState(() {
          _likedSongs = cachedLikedSongs;
          _playlists = cachedPlaylists;
        });
      }

      final isOnline = await _networkStatus.isOnline();
      if (!isOnline) {
        if (mounted) {
          setState(() {
            _isOfflineMode = true;
            _isLoading = false;
          });
        }
        return;
      }

      List<Song> likedSongs = cachedLikedSongs;
      List<Map<String, dynamic>> playlists = cachedPlaylists;

      try {
        likedSongs = await _musicService.getLikedSongs();
        await _offlineLibrary.cacheLikedSongs(likedSongs);
      } catch (_) {}

      try {
        playlists = await _musicService.getMyPlaylists();
        await _offlineLibrary.cachePlaylists(playlists);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _likedSongs = likedSongs;
          _playlists = playlists;
          _isOfflineMode = false;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isOfflineMode = false;
          _isLoading = false;
        });
      }
    }
  }

  void _showCreatePlaylistDialog() {
    String newName = '';
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('New Playlist'),
          content: TextField(
            onChanged: (value) => newName = value,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Playlist Name',
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
              onPressed: () {
                if (newName.trim().isNotEmpty) {
                  _createPlaylist(newName.trim());
                }
                Navigator.pop(context);
              },
              child: const Text(
                'Add',
                style: TextStyle(color: Color(0xFF0B3B8C)),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createPlaylist(String name) async {
    final isOnline = await _networkStatus.isOnline();
    if (!isOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You are offline. Reconnect to create playlists.'),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    try {
      final result = await _musicService.createPlaylist(name);
      if (!mounted) return;

      if (result['success'] == true && result['data'] != null) {
        setState(() {
          _playlists.insert(0, Map<String, dynamic>.from(result['data']));
        });
        await _offlineLibrary.cachePlaylists(_playlists);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message']?.toString() ?? 'Could not create playlist',
            ),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create playlist: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  int _playlistSongCount(Map<String, dynamic> playlist) {
    final songs = playlist['songs'];
    if (songs is List) {
      return songs.length;
    }

    final songCount = playlist['song_count'] ?? playlist['songCount'];
    if (songCount is int) {
      return songCount;
    }
    return int.tryParse(songCount?.toString() ?? '') ?? 0;
  }

  Future<void> _downloadPlaylistAudio(Map<String, dynamic> playlist) async {
    final playlistId = (playlist['_id'] ?? '').toString().trim();
    final playlistNameFallback = (playlist['name'] ?? 'Playlist').toString();

    if (playlistId.isEmpty ||
        _playlistDownloadsInProgress.contains(playlistId)) {
      return;
    }

    setState(() {
      _playlistDownloadsInProgress.add(playlistId);
    });

    try {
      Map<String, dynamic>? details;
      final isOnline = await _networkStatus.isOnline();
      if (isOnline) {
        details = await _musicService.getPlaylist(playlistId);
      }
      details ??= await _offlineLibrary.getCachedPlaylist(playlistId);

      if (!mounted) {
        return;
      }

      if (details == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not load playlist for download'),
            backgroundColor: Colors.red[700],
          ),
        );
        return;
      }

      final playlistName = (details['name'] ?? playlistNameFallback)
          .toString()
          .trim();
      final rawSongs = details['songs'] as List<dynamic>? ?? const [];
      final songs = rawSongs
          .whereType<Map>()
          .map((item) => Song.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      if (songs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Playlist has no songs to download'),
            backgroundColor: Colors.orange[700],
          ),
        );
        return;
      }

      await _offlineLibrary.cachePlaylist(playlistId, playlistName, songs);
      final result = await _audioCache.downloadMissingSongs(songs);

      if (!mounted) {
        return;
      }

      final downloaded = _toInt(result['downloaded']);
      final skipped = _toInt(result['skipped']);
      final failed = _toInt(result['failed']);
      final downloadedBytes = _toInt(result['downloaded_bytes']);
      final downloadedMb = downloadedBytes / (1024 * 1024);

      final message = failed > 0
          ? '$playlistName: $downloaded downloaded, $skipped cached, $failed failed.'
          : '$playlistName: $downloaded downloaded, $skipped cached (${downloadedMb.toStringAsFixed(1)} MB).';

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
          _playlistDownloadsInProgress.remove(playlistId);
        });
      }
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your Library',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                if (_isLoggedIn)
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 28),
                    onPressed: _showCreatePlaylistDialog,
                  ),
              ],
            ),
            if (_isOfflineMode)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2112),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF8A6A35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, color: Color(0xFFF6C977), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline mode: showing cached library content.',
                        style: TextStyle(color: Color(0xFFF6C977), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF0B3B8C)),
                ),
              )
            else if (!_isLoggedIn)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.library_music_rounded,
                        color: Colors.grey[600],
                        size: 60,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Log in to view your library',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.of(
                          context,
                          rootNavigator: true,
                        ).pushNamedAndRemoveUntil('/login', (route) => false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B3B8C),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text('Log In'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  color: const Color(0xFF0B3B8C),
                  child: ListView(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF143673),
                              Color(0xFF112954),
                              Color(0xFF1B1B1B),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          title: const Text(
                            'Liked Songs',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            '${_likedSongs.length} songs',
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 13,
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.grey[300],
                            size: 16,
                          ),
                          onTap: widget.onOpenLikedSongs,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Playlists',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${_playlists.length}',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_playlists.isEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D1D1D),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.queue_music_rounded,
                                color: Colors.grey[500],
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'No playlists yet. Tap + to create one.',
                                style: TextStyle(color: Colors.grey[400]),
                              ),
                            ],
                          ),
                        ),
                      ..._playlists.map((playlist) {
                        final playlistId = (playlist['_id'] ?? '')
                            .toString()
                            .trim();
                        final isDownloading = _playlistDownloadsInProgress
                            .contains(playlistId);

                        return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1D1D1D),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              leading: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: const Color(0xFF2A2A2A),
                                ),
                                child: const Icon(
                                  Icons.queue_music_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                (playlist['name'] ?? 'Untitled Playlist')
                                    .toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Text(
                                '${_playlistSongCount(playlist)} songs',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 13,
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: isDownloading
                                    ? 'Downloading audio...'
                                    : 'Download missing audio',
                                onPressed: playlistId.isEmpty || isDownloading
                                    ? null
                                    : () => _downloadPlaylistAudio(playlist),
                                icon: isDownloading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.download_rounded),
                              ),
                              onTap: () {
                                if (playlistId.isEmpty) {
                                  return;
                                }
                                widget.onOpenPlaylist(playlistId);
                              },
                            ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
