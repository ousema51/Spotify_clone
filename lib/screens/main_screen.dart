import 'dart:math';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' show PlayerState;
import '../models/song.dart';
import '../services/auth_service.dart';
import '../services/music_service.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/full_player.dart';
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
  bool _isFullPlayer = false;
  Song? _currentSong;
  final AuthService _authService = AuthService();
  final PlayerService _player = PlayerService();
  final MusicService _musicService = MusicService();

  List<Song> _playQueue = [];
  int _queueIndex = -1;
  bool _shuffleEnabled = false;
  QueueRepeatMode _repeatMode = QueueRepeatMode.off;
  bool _lastSelectionFromSearch = false;
  bool _isHandlingEnded = false;
  LibraryView _libraryView = LibraryView.library;
  String? _activePlaylistId;
  int _libraryRefreshKey = 0;
  BrowseView _browseView = BrowseView.none;
  String? _activeArtistId;
  String? _activeAlbumId;

  @override
  void initState() {
    super.initState();
    _player.playerStateNotifier.addListener(_onPlayerStateChanged);
  }

  @override
  void dispose() {
    _player.playerStateNotifier.removeListener(_onPlayerStateChanged);
    super.dispose();
  }

  void _onPlayerStateChanged() {
    if (_player.playerStateNotifier.value == PlayerState.ended) {
      _handleTrackEnded();
    }
  }

  void _onSongSelected(Song song, [List<Song>? queue]) {
    _lastSelectionFromSearch = _selectedIndex == 1;

    if (queue != null && queue.isNotEmpty) {
      _playQueue = List<Song>.from(queue);
      _queueIndex = _playQueue.indexWhere((s) => s.id == song.id);
      if (_queueIndex < 0) {
        _playQueue.insert(0, song);
        _queueIndex = 0;
      }
    } else {
      _playQueue = [song];
      _queueIndex = 0;
    }

    setState(() => _currentSong = song);
    _loadAndPlay(song);
    _trackListen(song);
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

  Future<void> _loadAndPlay(Song song) async {
    // song.id is the YouTube videoId from search results
    debugPrint('[MainScreen] playing song: ${song.title} (${song.id})');

    // Playback is handled by YouTube player controller using song video ID
    try {
      final streamUrl = await _musicService.getStreamUrlWithHint(
        song.id,
        song.title,
      );
      await _player.loadSong(song, streamUrl: streamUrl);
    } catch (e) {
      debugPrint('[MainScreen] _loadAndPlay error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playback error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleTrackEnded() async {
    if (_isHandlingEnded || _currentSong == null) return;
    _isHandlingEnded = true;

    try {
      if (_repeatMode == QueueRepeatMode.one) {
        await _loadAndPlay(_currentSong!);
        return;
      }

      final next = await _resolveNextSongAfterEnd();
      if (next != null) {
        setState(() => _currentSong = next);
        await _loadAndPlay(next);
      }
    } finally {
      _isHandlingEnded = false;
    }
  }

  Future<Song?> _resolveNextSongAfterEnd() async {
    if (_playQueue.isNotEmpty && _queueIndex >= 0) {
      if (_shuffleEnabled && _playQueue.length > 1) {
        final rand = Random();
        int nextIndex = _queueIndex;
        while (nextIndex == _queueIndex) {
          nextIndex = rand.nextInt(_playQueue.length);
        }
        _queueIndex = nextIndex;
        return _playQueue[_queueIndex];
      }

      final int nextIndex = _queueIndex + 1;
      if (nextIndex < _playQueue.length) {
        _queueIndex = nextIndex;
        return _playQueue[_queueIndex];
      }

      if (_repeatMode == QueueRepeatMode.all && _playQueue.isNotEmpty) {
        _queueIndex = 0;
        return _playQueue[_queueIndex];
      }
    }

    if (_lastSelectionFromSearch && _currentSong != null) {
      final query =
          '${_currentSong!.artist ?? ''} ${_currentSong!.title}'.trim();
      if (query.isNotEmpty) {
        final similar = await _musicService.searchSongs(query);
        final filtered = similar
            .where((s) => s.id != _currentSong!.id)
            .toList(growable: false);
        if (filtered.isNotEmpty) {
          _playQueue = filtered;
          _queueIndex = 0;
          return _playQueue.first;
        }
      }
    }

    return null;
  }

  Future<void> _playNextSong() async {
    final next = await _resolveNextSongAfterEnd();
    if (next != null) {
      setState(() => _currentSong = next);
      await _loadAndPlay(next);
    }
  }

  Future<void> _playPreviousSong() async {
    if (_playQueue.isEmpty || _queueIndex < 0) return;

    if (_shuffleEnabled && _playQueue.length > 1) {
      final rand = Random();
      int prevIndex = _queueIndex;
      while (prevIndex == _queueIndex) {
        prevIndex = rand.nextInt(_playQueue.length);
      }
      _queueIndex = prevIndex;
      final song = _playQueue[_queueIndex];
      setState(() => _currentSong = song);
      await _loadAndPlay(song);
      return;
    }

    final prevIndex = _queueIndex - 1;
    if (prevIndex >= 0) {
      _queueIndex = prevIndex;
      final song = _playQueue[_queueIndex];
      setState(() => _currentSong = song);
      await _loadAndPlay(song);
      return;
    }

    if (_repeatMode == QueueRepeatMode.all && _playQueue.isNotEmpty) {
      _queueIndex = _playQueue.length - 1;
      final song = _playQueue[_queueIndex];
      setState(() => _currentSong = song);
      await _loadAndPlay(song);
    }
  }

  Future<bool> _addSongToQueue(Song song, [List<Song>? sourceQueue]) async {
    final bool alreadyQueued = _playQueue.any((s) => s.id == song.id);
    if (alreadyQueued) {
      return false;
    }

    setState(() {
      _playQueue.add(song);
      if (_queueIndex < 0 && _currentSong == null) {
        _queueIndex = 0;
      }
    });

    // If nothing is currently playing, start the queued song immediately.
    if (_currentSong == null) {
      setState(() => _currentSong = song);
      await _loadAndPlay(song);
    }

    return true;
  }

  void _toggleShuffle() {
    setState(() => _shuffleEnabled = !_shuffleEnabled);
  }

  void _cycleRepeatMode() {
    setState(() {
      _repeatMode = QueueRepeatMode
          .values[(_repeatMode.index + 1) % QueueRepeatMode.values.length];
    });
  }

  void _toggleFullPlayer() {
    setState(() => _isFullPlayer = !_isFullPlayer);
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

  Future<void> _openArtistFromName(String? artistName) async {
    final name = (artistName ?? '').trim();
    if (name.isEmpty) return;

    final artists = await _musicService.searchArtists(name);
    if (artists.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Artist page not found'),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    setState(() {
      _isFullPlayer = false;
      _activeArtistId = artists.first.id;
      _browseView = BrowseView.artist;
    });
  }

  void _closeBrowseView() {
    setState(() {
      _browseView = BrowseView.none;
      _activeArtistId = null;
      _activeAlbumId = null;
    });
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
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
                          onPressed: () =>
                              Navigator.pushNamed(context, '/login'),
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
              MiniPlayer(onTap: _toggleFullPlayer, currentSong: _currentSong),
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
        if (_isFullPlayer)
          FullPlayerScreen(
            onClose: _toggleFullPlayer,
            currentSong: _currentSong,
            isShuffle: _shuffleEnabled,
            repeatMode: _repeatMode,
            onToggleShuffle: _toggleShuffle,
            onCycleRepeatMode: _cycleRepeatMode,
            onNext: _playNextSong,
            onPrevious: _playPreviousSong,
            onArtistTap: _openArtistFromName,
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
