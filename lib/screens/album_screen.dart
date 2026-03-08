import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../services/music_service.dart';
import '../widgets/song_tile.dart';

class AlbumScreen extends StatefulWidget {
  final String albumId;
  final Function(Song) onSongSelected;

  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.onSongSelected,
  });

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  final MusicService _musicService = MusicService();
  Album? _album;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbum();
  }

  Future<void> _loadAlbum() async {
    setState(() => _isLoading = true);
    try {
      final album = await _musicService.getAlbum(widget.albumId);
      if (mounted) {
        setState(() {
          _album = album;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load album: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1DB954)))
          : _album == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.grey[600], size: 48),
                      const SizedBox(height: 12),
                      const Text('Album not found',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go back',
                            style: TextStyle(color: Color(0xFF1DB954))),
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      expandedHeight: 300,
                      pinned: true,
                      backgroundColor: const Color(0xFF121212),
                      flexibleSpace: FlexibleSpaceBar(
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            _album!.coverUrl != null &&
                                    _album!.coverUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: _album!.coverUrl!,
                                    placeholder: (context, url) => Container(
                                        color: const Color(0xFF282828)),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                          color: const Color(0xFF282828),
                                          child: const Icon(
                                              Icons.album_rounded,
                                              color: Colors.white54,
                                              size: 80),
                                        ),
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: const Color(0xFF282828),
                                    child: const Icon(Icons.album_rounded,
                                        color: Colors.white54, size: 80),
                                  ),
                            // Gradient overlay
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Color(0xFF121212),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _album!.title,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (_album!.artist != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _album!.artist!,
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey[400]),
                              ),
                            ],
                            const SizedBox(height: 20),
                            // Shuffle button
                            ElevatedButton.icon(
                              onPressed: _album!.songs?.isNotEmpty == true
                                  ? () {
                                      final songs =
                                          List<Song>.from(_album!.songs!);
                                      songs.shuffle();
                                      widget.onSongSelected(songs.first);
                                      Navigator.pop(context);
                                    }
                                  : null,
                              icon: const Icon(Icons.shuffle_rounded),
                              label: const Text('Shuffle play'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1DB954),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    if (_album!.songs != null && _album!.songs!.isNotEmpty)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final song = _album!.songs![index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              child: SongTile(
                                song: song,
                                onTap: () {
                                  widget.onSongSelected(song);
                                  Navigator.pop(context);
                                },
                              ),
                            );
                          },
                          childCount: _album!.songs!.length,
                        ),
                      ),
                    const SliverToBoxAdapter(
                        child: SizedBox(height: 32)),
                  ],
                ),
    );
  }
}
