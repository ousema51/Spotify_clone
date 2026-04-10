import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/music_service.dart';
import '../services/offline_library_service.dart';
import '../widgets/song_tile.dart';

class LikedSongsScreen extends StatefulWidget {
  final void Function(Song, [List<Song>?]) onSongSelected;
  final Future<bool> Function(Song, [List<Song>?]) onAddToQueue;
  final VoidCallback onBack;

  const LikedSongsScreen({
    super.key,
    required this.onSongSelected,
    required this.onAddToQueue,
    required this.onBack,
  });

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  final MusicService _musicService = MusicService();
  final OfflineLibraryService _offlineLibrary = OfflineLibraryService();
  bool _isLoading = true;
  List<Song> _likedSongs = [];
  List<Map<String, dynamic>> _playlists = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final likedSongs = await _musicService.getLikedSongs();
      final playlists = await _musicService.getMyPlaylists();

      if (!mounted) return;
      setState(() {
        _likedSongs = likedSongs;
        _playlists = playlists;
        _isLoading = false;
      });
    } catch (_) {
      final cachedLiked = await _offlineLibrary.getCachedLikedSongs();
      if (!mounted) return;
      setState(() {
        _likedSongs = cachedLiked;
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadLibrary() async {
    final count = await _offlineLibrary.cacheLikedSongs(_likedSongs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved $count songs for offline library access.'),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  Future<void> _unlikeSong(Song song) async {
    final result = await _musicService.unlikeSong(song.id);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _likedSongs.removeWhere((s) => s.id == song.id);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Could not unlike song'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  int _playlistSongCount(Map<String, dynamic> playlist) {
    final songs = playlist['songs'];
    return songs is List ? songs.length : 0;
  }

  Future<void> _showChoosePlaylistForSong(Song song) async {
    if (_playlists.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Create a playlist first in Library'),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    final parentContext = context;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _playlists.length,
            itemBuilder: (context, index) {
              final playlist = _playlists[index];
              final playlistName =
                  (playlist['name'] ?? 'Untitled Playlist').toString();
              final playlistId = (playlist['_id'] ?? '').toString();

              return ListTile(
                leading: const Icon(Icons.queue_music_rounded,
                    color: Colors.white70),
                title: Text(playlistName),
                subtitle: Text(
                  '${_playlistSongCount(playlist)} songs',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                onTap: () async {
                  final navigator = Navigator.of(parentContext);
                  final messenger = ScaffoldMessenger.of(parentContext);
                  final result =
                      await _musicService.addSongToPlaylist(playlistId, song);

                  if (!mounted) return;
                  navigator.pop();
                  if (result['success'] == true) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Added to $playlistName'),
                        backgroundColor: Colors.green[700],
                      ),
                    );
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          result['message']?.toString() ??
                              'Could not add to playlist',
                        ),
                        backgroundColor: Colors.red[700],
                      ),
                    );
                  }
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: const Text('Liked Songs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download library',
            onPressed: _likedSongs.isEmpty ? null : _downloadLibrary,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0B3B8C)),
            )
          : _likedSongs.isEmpty
              ? Center(
                  child: Text(
                    'No liked songs yet',
                    style: TextStyle(color: Colors.grey[400], fontSize: 16),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: const Color(0xFF0B3B8C),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: _likedSongs.length,
                    itemBuilder: (context, index) {
                      final song = _likedSongs[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        title: SongTile(
                          song: song,
                          onTap: () => widget.onSongSelected(song, _likedSongs),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'add_to_playlist') {
                              _showChoosePlaylistForSong(song);
                            } else if (value == 'add_to_queue') {
                              final messenger = ScaffoldMessenger.of(context);
                              final added =
                                  await widget.onAddToQueue(song, _likedSongs);
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    added
                                        ? 'Added to queue'
                                        : 'Song is already in queue',
                                  ),
                                  backgroundColor:
                                      added ? Colors.green[700] : Colors.orange[700],
                                ),
                              );
                            } else if (value == 'remove_liked') {
                              _unlikeSong(song);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'add_to_playlist',
                              child: Text('Add to playlist'),
                            ),
                            PopupMenuItem(
                              value: 'add_to_queue',
                              child: Text('Add to queue'),
                            ),
                            PopupMenuItem(
                              value: 'remove_liked',
                              child: Text('Remove from liked songs'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

