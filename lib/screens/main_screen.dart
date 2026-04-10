import 'dart:async';

import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/auth_service.dart';
import '../services/music_service.dart';
import '../services/player_service.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'liked_songs_screen.dart';
import 'playlist_detail_screen.dart';
import 'artist_screen.dart';
import 'album_screen.dart';

enum LibraryView { library, likedSongs, playlist }

enum BrowseView { none, artist, album }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  Song? _currentSong;
  final AuthService _authService = AuthService();
  final MusicService _musicService = MusicService();
  final PlayerService _player = PlayerService();
  int _playRequestNonce = 0;
  final List<Song> _playQueue = [];
  int _queueIndex = -1;

  final List<Song> _queuedSongs = [];

  LibraryView _libraryView = LibraryView.library;
  String? _activePlaylistId;
  int _libraryRefreshKey = 0;
  BrowseView _browseView = BrowseView.none;
  String? _activeArtistId;
  String? _activeAlbumId;

  void _onSongSelected(Song song, [List<Song>? queue]) {
    setState(() {
      _primePlayQueue(song, queue);
      _currentSong = song;
    });
    unawaited(_resolveAndPlaySong(song));
    unawaited(_trackListen(song));
  }

  void _primePlayQueue(Song song, [List<Song>? queue]) {
    if (queue != null && queue.isNotEmpty) {
      _playQueue
        ..clear()
        ..addAll(queue);

      final index = _playQueue.indexWhere((candidate) => _sameSong(candidate, song));
      if (index >= 0) {
        _queueIndex = index;
      } else {
        _playQueue.insert(0, song);
        _queueIndex = 0;
      }
      return;
    }

    if (_playQueue.isEmpty) {
      _playQueue.add(song);
      _queueIndex = 0;
      return;
    }

    final existing = _playQueue.indexWhere((candidate) => _sameSong(candidate, song));
    if (existing >= 0) {
      _queueIndex = existing;
      return;
    }

    _playQueue.add(song);
    _queueIndex = _playQueue.length - 1;
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

  Future<void> _resolveAndPlaySong(Song song) async {
    final requestId = ++_playRequestNonce;

    try {
      final streamResult = await _musicService.getStreamDataWithHint(
        song.id,
        queryHint: _buildPlaybackQueryHint(song),
        titleHint: song.title,
      );

      if (!mounted || requestId != _playRequestNonce) {
        return;
      }

      if (streamResult['success'] != true) {
        final message = streamResult['message']?.toString() ?? 'Unable to resolve stream data';
        _showPlaybackError(message);
        return;
      }

      final dynamic rawData = streamResult['data'];
      if (rawData is! Map) {
        _showPlaybackError('Invalid stream response payload');
        return;
      }

      final data = Map<String, dynamic>.from(rawData);
      final audioUrl = (data['audio_url']?.toString() ?? '').trim();
      if (audioUrl.isEmpty) {
        _showPlaybackError('Missing audio URL for playback');
        return;
      }

      final rawHeaders = data['headers'];
      final headers = rawHeaders is Map<String, dynamic>
          ? rawHeaders
          : (rawHeaders is Map ? Map<String, dynamic>.from(rawHeaders) : null);

      await _player.playStream(
        song: song,
        audioUrl: audioUrl,
        headers: headers,
      );
    } catch (e) {
      if (!mounted || requestId != _playRequestNonce) {
        return;
      }
      _showPlaybackError('Playback failed: $e');
    }
  }

  void _showPlaybackError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  bool get _canPlayNext {
    if (_playQueue.isEmpty || _queueIndex < 0) {
      return false;
    }
    return _queueIndex + 1 < _playQueue.length;
  }

  bool get _canPlayPrevious {
    if (_playQueue.isEmpty || _queueIndex <= 0) {
      return false;
    }
    return true;
  }

  bool get _hasPreviousSong {
    if (_canPlayPrevious) {
      return true;
    }

    final current = _currentSong;
    if (current == null) {
      return false;
    }

    final index = _queuedSongs.indexWhere((song) => _sameSong(song, current));
    return index > 0;
  }

  bool get _hasNextSong {
    if (_canPlayNext) {
      return true;
    }

    final current = _currentSong;
    if (current == null) {
      return _queuedSongs.isNotEmpty;
    }

    final index = _queuedSongs.indexWhere((song) => _sameSong(song, current));
    if (index >= 0) {
      return index + 1 < _queuedSongs.length;
    }

    return _queuedSongs.any((song) => !_sameSong(song, current));
  }

  Future<void> _togglePlayPause() async {
    if (_currentSong == null) {
      return;
    }

    final state = _player.playbackStateNotifier.value;

    try {
      if (state == PlayerPlaybackState.playing) {
        await _player.pause();
        return;
      }

      if (state == PlayerPlaybackState.paused || state == PlayerPlaybackState.completed) {
        await _player.play();
        return;
      }

      await _resolveAndPlaySong(_currentSong!);
    } catch (e) {
      _showPlaybackError('Playback control failed: $e');
    }
  }

  Future<void> _playNextSong() async {
    if (_canPlayNext) {
      final nextIndex = _queueIndex + 1;
      final nextSong = _playQueue[nextIndex];
      setState(() {
        _queueIndex = nextIndex;
        _currentSong = nextSong;
      });
      await _resolveAndPlaySong(nextSong);
      unawaited(_trackListen(nextSong));
      return;
    }

    final current = _currentSong;
    if (current != null) {
      final queuedIndex = _queuedSongs.indexWhere((song) => _sameSong(song, current));
      if (queuedIndex >= 0 && queuedIndex + 1 < _queuedSongs.length) {
        final nextSong = _queuedSongs[queuedIndex + 1];
        setState(() {
          _currentSong = nextSong;
        });
        await _resolveAndPlaySong(nextSong);
        unawaited(_trackListen(nextSong));
        return;
      }
    }

    for (final queued in _queuedSongs) {
      if (_currentSong != null && _sameSong(queued, _currentSong!)) {
        continue;
      }
      setState(() {
        _currentSong = queued;
      });
      await _resolveAndPlaySong(queued);
      unawaited(_trackListen(queued));
      return;
    }

    _showPlaybackError('No next song available in queue');
  }

  Future<void> _playPreviousSong() async {
    if (_canPlayPrevious) {
      final previousIndex = _queueIndex - 1;
      final previousSong = _playQueue[previousIndex];
      setState(() {
        _queueIndex = previousIndex;
        _currentSong = previousSong;
      });
      await _resolveAndPlaySong(previousSong);
      unawaited(_trackListen(previousSong));
      return;
    }

    final current = _currentSong;
    if (current != null) {
      final queuedIndex = _queuedSongs.indexWhere((song) => _sameSong(song, current));
      if (queuedIndex > 0) {
        final previousSong = _queuedSongs[queuedIndex - 1];
        setState(() {
          _currentSong = previousSong;
        });
        await _resolveAndPlaySong(previousSong);
        unawaited(_trackListen(previousSong));
        return;
      }
    }

    _showPlaybackError('No previous song available in queue');
  }

  Widget _buildPlaybackControls() {
    final song = _currentSong;
    if (song == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                ValueListenableBuilder<PlayerPlaybackState>(
                  valueListenable: _player.playbackStateNotifier,
                  builder: (context, state, child) {
                    final isLoading = state == PlayerPlaybackState.loading;
                    if (isLoading) {
                      return Row(
                        children: [
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Buffering...',
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      );
                    }

                    return Text(
                      song.artist ?? 'Unknown Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          ValueListenableBuilder<PlayerPlaybackState>(
            valueListenable: _player.playbackStateNotifier,
            builder: (context, state, child) {
              final isLoading = state == PlayerPlaybackState.loading;
              final isPlaying = state == PlayerPlaybackState.playing;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: isLoading || !_hasPreviousSong
                        ? null
                        : () => unawaited(_playPreviousSong()),
                    icon: Icon(
                      Icons.skip_previous_rounded,
                      color: _hasPreviousSong ? Colors.white : Colors.grey[600],
                    ),
                  ),
                  IconButton(
                    onPressed: isLoading ? null : () => unawaited(_togglePlayPause()),
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                          ),
                  ),
                  IconButton(
                    onPressed: isLoading || !_hasNextSong
                        ? null
                        : () => unawaited(_playNextSong()),
                    icon: Icon(
                      Icons.skip_next_rounded,
                      color: _hasNextSong ? Colors.white : Colors.grey[600],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _trackListen(Song song) async {
    try {
      await _musicService.trackListen(
        song.id,
        song.toMetadata(),
        0,
        song.duration ?? 0,
      );
    } catch (_) {}
  }

  bool _sameSong(Song a, Song b) {
    if (a.id.isNotEmpty && b.id.isNotEmpty) {
      return a.id == b.id;
    }
    return a.title == b.title && (a.artist ?? '') == (b.artist ?? '');
  }

  Future<bool> _addSongToQueue(Song song, [List<Song>? sourceQueue]) async {
    final alreadyQueued = _queuedSongs.any((existing) => _sameSong(existing, song));
    if (alreadyQueued) {
      return false;
    }

    setState(() {
      _queuedSongs.add(song);
      _currentSong ??= song;
    });

    return true;
  }

  void _openPlaylist(String playlistId) {
    setState(() {
      _activePlaylistId = playlistId;
      _libraryView = LibraryView.playlist;
      _selectedIndex = 2;
    });
  }

  void _openLikedSongs() {
    setState(() {
      _libraryView = LibraryView.likedSongs;
      _selectedIndex = 2;
    });
  }

  void _closeLibrarySubView({bool refresh = false}) {
    setState(() {
      _libraryView = LibraryView.library;
      _activePlaylistId = null;
      if (refresh) {
        _libraryRefreshKey++;
      }
    });
  }

  void _openArtist(String artistId) {
    setState(() {
      _activeArtistId = artistId;
      _browseView = BrowseView.artist;
    });
  }

  void _openAlbum(String albumId) {
    setState(() {
      _activeAlbumId = albumId;
      _browseView = BrowseView.album;
    });
  }

  void _closeBrowseView() {
    setState(() {
      _browseView = BrowseView.none;
      _activeArtistId = null;
      _activeAlbumId = null;
    });
  }

  void _openLogin() {
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _logout() async {
    try {
      await _authService.logout();
    } catch (_) {
      // Always route to login even if remote logout fails.
    }
    if (mounted) {
      _openLogin();
    }
  }

  @override
  void dispose() {
    unawaited(_player.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget libraryContent;
    if (_libraryView == LibraryView.playlist && _activePlaylistId != null) {
      libraryContent = PlaylistDetailScreen(
        playlistId: _activePlaylistId!,
        onSongSelected: _onSongSelected,
        onAddToQueue: _addSongToQueue,
        onBack: (refresh) => _closeLibrarySubView(refresh: refresh),
      );
    } else if (_libraryView == LibraryView.likedSongs) {
      libraryContent = LikedSongsScreen(
        onSongSelected: _onSongSelected,
        onAddToQueue: _addSongToQueue,
        onBack: _closeLibrarySubView,
      );
    } else {
      libraryContent = LibraryScreen(
        key: ValueKey('library-$_libraryRefreshKey'),
        onSongSelected: _onSongSelected,
        onOpenPlaylist: _openPlaylist,
        onOpenLikedSongs: _openLikedSongs,
      );
    }

    final pages = [
      HomeScreen(onSongSelected: _onSongSelected),
      SearchScreen(
        onSongSelected: _onSongSelected,
        onArtistSelected: _openArtist,
        onAlbumSelected: _openAlbum,
      ),
      libraryContent,
    ];

    Widget bodyContent = Expanded(child: pages[_selectedIndex]);

    if (_browseView == BrowseView.artist && _activeArtistId != null) {
      bodyContent = Expanded(
        child: ArtistScreen(
          artistId: _activeArtistId!,
          onSongSelected: _onSongSelected,
          onAlbumSelected: _openAlbum,
        ),
      );
    } else if (_browseView == BrowseView.album && _activeAlbumId != null) {
      bodyContent = Expanded(
        child: AlbumScreen(
          albumId: _activeAlbumId!,
          onSongSelected: _onSongSelected,
        ),
      );
    }

    return Stack(
      children: [
        Scaffold(
          appBar: _selectedIndex == 0
              ? AppBar(
                  backgroundColor: const Color(0xFF121212),
                  elevation: 0,
                  actions: [
                    FutureBuilder<bool>(
                      future: _authService.isLoggedIn(),
                      builder: (context, snapshot) {
                        if (snapshot.data == true) {
                          return IconButton(
                            icon: const Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                            ),
                            tooltip: 'Logout',
                            onPressed: _logout,
                          );
                        }
                        return TextButton(
                          onPressed: _openLogin,
                          child: const Text(
                            'Log In',
                            style: TextStyle(color: Color(0xFF0B3B8C)),
                          ),
                        );
                      },
                    ),
                  ],
                )
              : null,
          body: Column(
            children: [
              bodyContent,
              if (_currentSong != null) _buildPlaybackControls(),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() {
              _selectedIndex = index;
              _browseView = BrowseView.none;
              _activeArtistId = null;
              _activeAlbumId = null;
              if (index != 2) {
                _libraryView = LibraryView.library;
                _activePlaylistId = null;
              }
            }),
            backgroundColor: const Color(0xFF1A1A1A),
            selectedItemColor: const Color(0xFF0B3B8C),
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search_rounded),
                label: 'Search',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.library_music_rounded),
                label: 'Library',
              ),
            ],
          ),
        ),
        if (_browseView != BrowseView.none)
          Positioned(
            top: 12,
            left: 10,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: _closeBrowseView,
              ),
            ),
          ),
      ],
    );
  }
}
