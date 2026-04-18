import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../services/music_service.dart';
import '../services/network_status_service.dart';
import '../services/offline_library_service.dart';
import '../widgets/song_tile.dart';

class AlbumScreen extends StatefulWidget {
  final String albumId;
  final void Function(Song, [List<Song>?]) onSongSelected;

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
  final OfflineLibraryService _offlineLibrary = OfflineLibraryService();
  final NetworkStatusService _networkStatus = NetworkStatusService();
  Album? _album;
  bool _isLoading = true;
  bool _isOfflineMode = false;

  @override
  void initState() {
    super.initState();
    _loadAlbum();
  }

  Future<void> _loadAlbum() async {
    setState(() => _isLoading = true);
    final cachedAlbum = await _offlineLibrary.getCachedAlbumPage(widget.albumId);

    if (cachedAlbum != null && mounted) {
      setState(() {
        _album = cachedAlbum;
      });
      await _offlineLibrary.markAlbumVisited(widget.albumId);
    }

    final isOnline = await _networkStatus.isOnline();
    if (!isOnline) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isOfflineMode = true;
        _isLoading = false;
      });
      return;
    }

    try {
      final album = await _musicService.getAlbum(widget.albumId);
      if (album != null) {
        await _offlineLibrary.cacheAlbumPage(album);
      }
      if (mounted) {
        setState(() {
          _album = album ?? cachedAlbum;
          _isOfflineMode = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _album = cachedAlbum;
          _isOfflineMode = cachedAlbum != null;
          _isLoading = false;
        });
        if (cachedAlbum == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load album: $e'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
        body: _isLoading
          ? const Center(
            child: CircularProgressIndicator(color: Color(0xFF0B3B8C)))
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
                          style: TextStyle(color: Color(0xFF0B3B8C))),
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      automaticallyImplyLeading: false,
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
                            if (_isOfflineMode)
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A2112),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF8A6A35),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.wifi_off_rounded,
                                      color: Color(0xFFF6C977),
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Offline mode: showing cached album page.',
                                        style: TextStyle(
                                          color: Color(0xFFF6C977),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                                      widget.onSongSelected(songs.first, songs);
                                    }
                                  : null,
                              icon: const Icon(Icons.shuffle_rounded),
                              label: const Text('Shuffle play'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0B3B8C),
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
                                  widget.onSongSelected(song, _album!.songs);
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

