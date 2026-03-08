import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/music_service.dart';
import '../services/auth_service.dart';
import '../widgets/song_tile.dart';

class LibraryScreen extends StatefulWidget {
  final Function(Song) onSongSelected;

  const LibraryScreen({super.key, required this.onSongSelected});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final MusicService _musicService = MusicService();
  final AuthService _authService = AuthService();
  List<Song> _likedSongs = [];
  List<String> _playlists = [];
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _isLoggedIn = await _authService.isLoggedIn();

    if (_isLoggedIn) {
      try {
        final likedSongs = await _musicService.getLikedSongs();
        if (mounted) {
          setState(() {
            _likedSongs = likedSongs;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddPlaylistDialog() {
    String newName = '';
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              child: Text('Cancel',
                  style: TextStyle(color: Colors.grey[400])),
            ),
            TextButton(
              onPressed: () {
                if (newName.isNotEmpty) {
                  setState(() => _playlists.add(newName));
                }
                Navigator.pop(context);
              },
              child: const Text('Add',
                  style: TextStyle(color: Color(0xFF1DB954))),
            ),
          ],
        );
      },
    );
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
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold),
                ),
                if (_isLoggedIn)
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 28),
                    onPressed: _showAddPlaylistDialog,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF1DB954)),
                ),
              )
            else if (!_isLoggedIn)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.library_music_rounded,
                          color: Colors.grey[600], size: 60),
                      const SizedBox(height: 16),
                      const Text(
                        'Log in to view your library',
                        style:
                            TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/login'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
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
                  color: const Color(0xFF1DB954),
                  child: ListView(
                    children: [
                      // Liked Songs card
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          leading: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF7B4FFF),
                                  Color(0xFF1DB954)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Icon(Icons.favorite_rounded,
                                color: Colors.white, size: 24),
                          ),
                          title: const Text(
                            'Liked Songs',
                            style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 15),
                          ),
                          subtitle: Text(
                            'Playlist • ${_likedSongs.length} songs',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 13),
                          ),
                          onTap: () => _showLikedSongs(),
                        ),
                      ),

                      // User playlists
                      ..._playlists.map((name) => Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              leading: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  color: const Color(0xFF282828),
                                ),
                                child: const Icon(
                                    Icons.music_note_rounded,
                                    color: Colors.white,
                                    size: 24),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 15),
                              ),
                              subtitle: Text(
                                'Playlist',
                                style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 13),
                              ),
                              onTap: () {},
                            ),
                          )),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showLikedSongs() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Liked Songs',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            if (_likedSongs.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No liked songs yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _likedSongs.length,
                  itemBuilder: (context, index) {
                    final song = _likedSongs[index];
                    return SongTile(
                      song: song,
                      onTap: () {
                        Navigator.pop(context);
                        widget.onSongSelected(song);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
