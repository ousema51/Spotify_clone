import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/auth_service.dart';
import '../services/music_service.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/full_player.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';

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

  void _onSongSelected(Song song) {
    // Set current song immediately for UI then attempt to load stream and play
    setState(() => _currentSong = song);
    _loadAndPlay(song);
  }

  Future<void> _loadAndPlay(Song song) async {
    final PlayerService player = PlayerService();
    // Ensure we have streamUrl; fetch full song if missing
    String? url = song.streamUrl;
    if (url == null || url.isEmpty) {
      final full = await MusicService().getSong(song.id);
      url = full?.streamUrl;
      if (full != null) {
        setState(() => _currentSong = full);
      }
    }
    if (url != null && url.isNotEmpty) {
      print('[MainScreen] playing url from backend: $url');
      final ok = await player.playUrl(url);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playback failed: unable to load stream')),
        );
      }
    } else {
      // Try resolving YouTube stream client-side using PlayerService
      final videoId = song.id;
      print('[MainScreen] no backend streamUrl, will try video id: $videoId');
      bool played = false;
      if (videoId != null && videoId.isNotEmpty) {
        // If running on Web, youtube_explode_dart cannot fetch YouTube streams due to CORS.
        if (true) {
          // Try backend stream endpoint first (works on Web because backend can fetch yt-dlp)
          final backendUrl = await MusicService().getStreamUrl(videoId);
          if (backendUrl != null && backendUrl.isNotEmpty) {
            print('[MainScreen] obtained backend stream url: $backendUrl');
            played = await player.playUrl(backendUrl);
          }
        }
        // If backend didn't provide stream, try client-side resolver (non-web only)
        if (!played) {
          played = await player.playYoutubeVideo(videoId);
        }
      }
      if (!played && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playback failed: no stream URL available. On Web this requires a backend stream proxy.')),
        );
      }
    }
  }

  void _toggleFullPlayer() {
    setState(() => _isFullPlayer = !_isFullPlayer);
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onSongSelected: _onSongSelected),
      SearchScreen(onSongSelected: _onSongSelected),
      LibraryScreen(onSongSelected: _onSongSelected),
    ];

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
                            icon: const Icon(Icons.logout_rounded,
                                color: Colors.white),
                            tooltip: 'Logout',
                            onPressed: _logout,
                          );
                        }
                        return TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/login'),
                          child: const Text('Log In',
                              style: TextStyle(color: Color(0xFF1DB954))),
                        );
                      },
                    ),
                  ],
                )
              : null,
          body: Column(
            children: [
              Expanded(child: pages[_selectedIndex]),
              MiniPlayer(
                onTap: _toggleFullPlayer,
                currentSong: _currentSong,
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
            backgroundColor: const Color(0xFF1A1A1A),
            selectedItemColor: const Color(0xFF1DB954),
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
          ),
      ],
    );
  }
}
