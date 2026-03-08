import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/artist.dart';
import '../models/song.dart';
import '../services/music_service.dart';
import '../widgets/song_tile.dart';
import '../widgets/album_card.dart';
import 'album_screen.dart';

class ArtistScreen extends StatefulWidget {
  final String artistId;
  final Function(Song) onSongSelected;

  const ArtistScreen({
    super.key,
    required this.artistId,
    required this.onSongSelected,
  });

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  final MusicService _musicService = MusicService();
  Artist? _artist;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArtist();
  }

  Future<void> _loadArtist() async {
    setState(() => _isLoading = true);
    try {
      final artist = await _musicService.getArtist(widget.artistId);
      if (mounted) {
        setState(() {
          _artist = artist;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load artist: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  String _formatFollowers(int? count) {
    if (count == null) return '';
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M followers';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K followers';
    }
    return '$count followers';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1DB954)))
          : _artist == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.grey[600], size: 48),
                      const SizedBox(height: 12),
                      const Text('Artist not found',
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
                      expandedHeight: 280,
                      pinned: true,
                      backgroundColor: const Color(0xFF121212),
                      flexibleSpace: FlexibleSpaceBar(
                        title: Text(
                          _artist!.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                  color: Colors.black,
                                  blurRadius: 8,
                                  offset: Offset(0, 2))
                            ],
                          ),
                        ),
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            _artist!.imageUrl != null &&
                                    _artist!.imageUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: _artist!.imageUrl!,
                                    placeholder: (context, url) => Container(
                                        color: const Color(0xFF282828)),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                          color: const Color(0xFF282828),
                                          child: const Icon(
                                              Icons.person_rounded,
                                              color: Colors.white54,
                                              size: 80),
                                        ),
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: const Color(0xFF282828),
                                    child: const Icon(Icons.person_rounded,
                                        color: Colors.white54, size: 80),
                                  ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Color(0x88000000),
                                    Color(0xFF121212),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: [0.0, 0.6, 1.0],
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
                            if (_artist!.followerCount != null) ...[
                              Text(
                                _formatFollowers(_artist!.followerCount),
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey[400]),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (_artist!.bio != null &&
                                _artist!.bio!.isNotEmpty) ...[
                              Text(
                                _artist!.bio!,
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey[300]),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_artist!.topSongs != null &&
                        _artist!.topSongs!.isNotEmpty) ...[
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Text(
                            'Top Songs',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final song = _artist!.topSongs![index];
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
                          childCount: _artist!.topSongs!.length,
                        ),
                      ),
                    ],
                    if (_artist!.topAlbums != null &&
                        _artist!.topAlbums!.isNotEmpty) ...[
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                          child: Text(
                            'Albums',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 190,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _artist!.topAlbums!.length,
                            itemBuilder: (context, index) {
                              final album = _artist!.topAlbums![index];
                              return AlbumCard(
                                album: album,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AlbumScreen(
                                      albumId: album.id,
                                      onSongSelected: widget.onSongSelected,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
    );
  }
}
