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
  final PlayerService _player = PlayerService();

  void _onSongSelected(Song song) {
    setState(() => _currentSong = song);
    _loadAndPlay(song);
  }

  Future<void> _loadAndPlay(Song song) async {
    // song.id is the YouTube videoId from search results
    print('[MainScreen] playing song: ${song.title} (${song.id})');

    // Refresh metadata (thumbnail, duration) from backend when available
    try {
      final fresh = await MusicService().getSong(song.id);
      if (fresh != null && mounted) {
        final t = (fresh.title ?? '').trim();
        if (t.isNotEmpty && t.toLowerCase() != 'unknown') {
          setState(() => _currentSong = fresh);
        }
      }
    } catch (_) {}

    // Try to obtain backend-resolved stream URL first
    try {
      final url = await MusicService().getStreamUrlWithHint(
        song.id,
        song.title,
      );
      bool played = false;
      if (url != null && url.isNotEmpty) {
        played = await _player.playUrl(url);
      }

      // Fallback: resolve on device if backend failed
      if (!played) {
        played = await _player.playSong(song);
      }

      if (!played && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Playback failed: could not load this song'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('[MainScreen] _loadAndPlay error: $e');
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
              Expanded(child: pages[_selectedIndex]),
              MiniPlayer(onTap: _toggleFullPlayer, currentSong: _currentSong),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
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
          ),
      ],
    );
  }
}
