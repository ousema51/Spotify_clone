import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/artist.dart';
import '../models/song.dart';
import '../services/music_service.dart';
import '../services/network_status_service.dart';
import '../services/offline_library_service.dart';
import '../services/user_activity_service.dart';
import '../widgets/song_tile.dart';

class HomeScreen extends StatefulWidget {
  final void Function(Song, [List<Song>?]) onSongSelected;
  final ValueChanged<String> onArtistSelected;

  const HomeScreen({
    super.key,
    required this.onSongSelected,
    required this.onArtistSelected,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MusicService _musicService = MusicService();
  final UserActivityService _activityService = UserActivityService();
  final OfflineLibraryService _offlineLibrary = OfflineLibraryService();
  final NetworkStatusService _networkStatus = NetworkStatusService();
  List<Song> _trending = [];
  List<Song> _suggestions = [];
  List<Map<String, dynamic>> _recentPlaylists = [];
  List<Artist> _recentArtists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final recentPlaylists = await _activityService.getRecentPlaylists();
    final recentArtists = await _offlineLibrary.getRecentArtistPages(limit: 10);

    if (mounted) {
      setState(() {
        _recentPlaylists = recentPlaylists;
        _recentArtists = recentArtists;
      });
    }

    final isOnline = await _networkStatus.isOnline();
    if (!isOnline) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final trending = await _musicService.getTrending();
      List<Song> suggestions = [];
      try {
        suggestions = await _musicService.getSuggestions();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _trending = trending;
          _suggestions = suggestions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0B3B8C)),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFF0B3B8C),
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

                  if (_recentPlaylists.isNotEmpty) ...[
                    const Text(
                      'Recently Played Playlists',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 90,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recentPlaylists.length,
                        itemBuilder: (context, index) {
                          final item = _recentPlaylists[index];
                          final name =
                              (item['name'] ?? 'Playlist').toString();
                          final cover = item['cover_url']?.toString();

                          return Container(
                            width: 190,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F1F1F),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: (cover != null && cover.isNotEmpty)
                                        ? CachedNetworkImage(
                                            imageUrl: cover,
                                            fit: BoxFit.cover,
                                            errorWidget:
                                                (context, url, error) => Container(
                                              color: const Color(0xFF282828),
                                              child: const Icon(
                                                Icons.queue_music_rounded,
                                                color: Colors.white54,
                                              ),
                                            ),
                                          )
                                        : Container(
                                            color: const Color(0xFF282828),
                                            child: const Icon(
                                              Icons.queue_music_rounded,
                                              color: Colors.white54,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],

                  if (_recentArtists.isNotEmpty) ...[
                    const Text(
                      'Recently Visited Artists',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 98,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recentArtists.length,
                        itemBuilder: (context, index) {
                          final artist = _recentArtists[index];
                          return GestureDetector(
                            onTap: () => widget.onArtistSelected(artist.id),
                            child: Container(
                              width: 88,
                              margin: const EdgeInsets.only(right: 12),
                              child: Column(
                                children: [
                                  ClipOval(
                                    child: SizedBox(
                                      width: 62,
                                      height: 62,
                                      child: (artist.imageUrl ?? '').trim().isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: artist.imageUrl!,
                                              fit: BoxFit.cover,
                                              errorWidget: (context, url, error) =>
                                                  Container(
                                                    color: const Color(0xFF282828),
                                                    child: const Icon(
                                                      Icons.person_rounded,
                                                      color: Colors.white54,
                                                    ),
                                                  ),
                                            )
                                          : Container(
                                              color: const Color(0xFF282828),
                                              child: const Icon(
                                                Icons.person_rounded,
                                                color: Colors.white54,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    artist.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

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
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _trending.length,
                            itemBuilder: (context, index) {
                              final song = _trending[index];
                              return ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: constraints.maxHeight,
                                ),
                                child: _TrendingCard(
                                  song: song,
                                  onTap: () => widget.onSongSelected(song, _trending),
                                ),
                              );
                            },
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
                    ..._suggestions.map(
                      (song) => SongTile(
                        song: song,
                        onTap: () => widget.onSongSelected(song, _suggestions),
                      ),
                    ),
                  ],

                  if (_trending.isEmpty &&
                      _suggestions.isEmpty)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 60),
                          Icon(
                            Icons.music_off_rounded,
                            color: Colors.grey[600],
                            size: 60,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No music available',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 16,
                            ),
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
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.expand(
                  child: song.coverUrl != null && song.coverUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: song.coverUrl!,
                          placeholder: (context, url) =>
                              Container(color: Colors.grey[800]),
                          errorWidget: (context, url, error) => Container(
                            color: const Color(0xFF282828),
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: Colors.white54,
                              size: 40,
                            ),
                          ),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: const Color(0xFF282828),
                          child: const Icon(
                            Icons.music_note_rounded,
                            color: Colors.white54,
                            size: 40,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
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

// ignore: unused_element
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
                          child: const Icon(
                            Icons.album_rounded,
                            color: Colors.grey,
                            size: 40,
                          ),
                        ),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: const Color(0xFF282828),
                        child: const Icon(
                          Icons.album_rounded,
                          color: Colors.grey,
                          size: 40,
                        ),
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

