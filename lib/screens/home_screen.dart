import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../services/music_service.dart';
import '../widgets/song_tile.dart';

class HomeScreen extends StatefulWidget {
  final Function(Song) onSongSelected;

  const HomeScreen({super.key, required this.onSongSelected});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MusicService _musicService = MusicService();
  List<Song> _trending = [];
  List<Song> _recentHistory = [];
  List<Song> _suggestions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final trending = await _musicService.getTrending();
      List<Song> recent = [];
      List<Song> suggestions = [];
      try {
        recent = await _musicService.getRecentHistory();
      } catch (_) {}
      try {
        suggestions = await _musicService.getSuggestions();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _trending = trending;
          _recentHistory = recent;
          _suggestions = suggestions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFF1DB954),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    _greeting(),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_trending.isNotEmpty) ...[
                    const Text(
                      'Trending Now',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _trending.length,
                        itemBuilder: (context, index) {
                          final song = _trending[index];
                          return _TrendingCard(
                            song: song,
                            onTap: () => widget.onSongSelected(song),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],

                  if (_recentHistory.isNotEmpty) ...[
                    const Text(
                      'Recently Played',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recentHistory.length,
                        itemBuilder: (context, index) {
                          final song = _recentHistory[index];
                          return _RecentCard(
                            song: song,
                            onTap: () => widget.onSongSelected(song),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],

                  if (_suggestions.isNotEmpty) ...[
                    const Text(
                      'Suggested For You',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._suggestions.map((song) => SongTile(
                          song: song,
                          onTap: () => widget.onSongSelected(song),
                        )),
                  ],

                  if (_trending.isEmpty &&
                      _recentHistory.isEmpty &&
                      _suggestions.isEmpty)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 60),
                          Icon(Icons.music_off_rounded,
                              color: Colors.grey[600], size: 60),
                          const SizedBox(height: 16),
                          Text(
                            'No music available',
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const _TrendingCard({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 140,
                height: 140,
                child: song.coverUrl != null && song.coverUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: song.coverUrl!,
                        placeholder: (context, url) =>
                            Container(color: Colors.grey[800]),
                        errorWidget: (context, url, error) => Container(
                          color: const Color(0xFF282828),
                          child: const Icon(Icons.music_note_rounded,
                              color: Colors.white54, size: 40),
                        ),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: const Color(0xFF282828),
                        child: const Icon(Icons.music_note_rounded,
                            color: Colors.white54, size: 40),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            if (song.artist != null)
              Text(
                song.artist!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const _RecentCard({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 120,
                child: song.coverUrl != null && song.coverUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: song.coverUrl!,
                        placeholder: (context, url) =>
                            Container(color: Colors.grey[800]),
                        errorWidget: (context, url, error) => Container(
                          color: const Color(0xFF282828),
                          child: const Icon(Icons.album_rounded,
                              color: Colors.grey, size: 40),
                        ),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: const Color(0xFF282828),
                        child: const Icon(Icons.album_rounded,
                            color: Colors.grey, size: 40),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
