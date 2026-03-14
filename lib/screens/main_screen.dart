import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/auth_service.dart';
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
    setState(() => _currentSong = song);
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
