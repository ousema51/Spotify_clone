import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/music_service.dart';
import '../services/offline_library_service.dart';
import '../services/user_activity_service.dart';
import '../widgets/song_tile.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;
  final void Function(Song, [List<Song>?]) onSongSelected;
  final Future<bool> Function(Song, [List<Song>?]) onAddToQueue;
  final ValueChanged<bool> onBack;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.onSongSelected,
    required this.onAddToQueue,
    required this.onBack,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final MusicService _musicService = MusicService();
  final OfflineLibraryService _offlineLibrary = OfflineLibraryService();
  final UserActivityService _activity = UserActivityService();

  Map<String, dynamic>? _playlist;
  List<Song> _songs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    setState(() => _isLoading = true);
    Map<String, dynamic>? playlist = await _musicService.getPlaylist(
      widget.playlistId,
    );

    playlist ??= await _offlineLibrary.getCachedPlaylist(widget.playlistId);

    if (!mounted) return;
    if (playlist == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not load playlist'),
          backgroundColor: Colors.red[700],
        ),
      );
      return;
    }

    final rawSongs = playlist['songs'] as List<dynamic>? ?? [];
    final songs = rawSongs
        .whereType<Map>()
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    setState(() {
      _playlist = playlist;
      _songs = songs;
      _isLoading = false;
    });
  }

  Future<void> _downloadPlaylistLibrary() async {
    final playlistName = (_playlist?['name'] ?? 'Playlist').toString();
    final count = await _offlineLibrary.cachePlaylist(
      widget.playlistId,
      playlistName,
      _songs,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved $count songs for offline library access. Streaming playback still requires internet for this source.',
        ),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  Future<void> _renamePlaylist() async {
    if (_playlist == null) return;

    final controller = TextEditingController(
      text: (_playlist!['name'] ?? '').toString(),
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Rename Playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Playlist name',
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
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save', style: TextStyle(color: Color(0xFF0B3B8C))),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty || _playlist == null) return;

    final result = await _musicService.renamePlaylist(widget.playlistId, newName);
    if (!mounted) return;

    if (result['success'] == true) {
      await _loadPlaylist();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Playlist renamed'),
          backgroundColor: Colors.green[700],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Could not rename playlist'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  Future<void> _deletePlaylist() async {
    if (_playlist == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Delete Playlist'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final result = await _musicService.deletePlaylist(widget.playlistId);
    if (!mounted) return;

    if (result['success'] == true) {
      widget.onBack(true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message']?.toString() ?? 'Could not delete playlist'),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  Future<void> _removeSong(Song song) async {
    final result =
        await _musicService.removeSongFromPlaylist(widget.playlistId, song.id);

    if (!mounted) return;

    if (result['success'] == true) {
      await _loadPlaylist();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message']?.toString() ?? 'Could not remove song'),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  Future<void> _confirmAndRemoveSong(Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Remove Song'),
          content: Text(
            'Remove "${song.title}" from this playlist?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _removeSong(song);
    }
  }

  Future<void> _showAddSongsSheet() async {
    final parentContext = context;
    final likedSongs = await _musicService.getLikedSongs();
    final searchController = TextEditingController();
    List<Song> searchResults = [];
    bool isSearching = false;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Add Songs',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search songs to add',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        prefixIcon:
                            Icon(Icons.search_rounded, color: Colors.grey[400]),
                        filled: true,
                        fillColor: const Color(0xFF282828),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (query) async {
                        setSheetState(() {
                          isSearching = true;
                        });
                        final results = await _musicService.searchSongs(query);
                        setSheetState(() {
                          searchResults = results;
                          isSearching = false;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    if (isSearching)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          color: Color(0xFF0B3B8C),
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        children: [
                          if (searchResults.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Search Results',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            ...searchResults.map(
                              (song) => ListTile(
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  song.artist ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                                trailing: const Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: Color(0xFF0B3B8C),
                                ),
                                onTap: () async {
                                  final navigator = Navigator.of(parentContext);
                                  final messenger =
                                      ScaffoldMessenger.of(parentContext);
                                  final res = await _musicService
                                      .addSongToPlaylist(widget.playlistId, song);
                                  if (!mounted) return;
                                  if (res['success'] == true) {
                                    navigator.pop();
                                    await _loadPlaylist();
                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: const Text('Song added'),
                                        backgroundColor: Colors.green[700],
                                      ),
                                    );
                                  } else {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          res['message']?.toString() ??
                                              'Could not add song',
                                        ),
                                        backgroundColor: Colors.red[700],
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Liked Songs',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (likedSongs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                'No liked songs yet',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          else
                            ...likedSongs.map(
                              (song) => ListTile(
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  song.artist ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                                trailing: const Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: Color(0xFF0B3B8C),
                                ),
                                onTap: () async {
                                  final navigator = Navigator.of(parentContext);
                                  final messenger =
                                      ScaffoldMessenger.of(parentContext);
                                  final res = await _musicService
                                      .addSongToPlaylist(widget.playlistId, song);
                                  if (!mounted) return;
                                  if (res['success'] == true) {
                                    navigator.pop();
                                    await _loadPlaylist();
                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: const Text('Song added'),
                                        backgroundColor: Colors.green[700],
                                      ),
                                    );
                                  } else {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          res['message']?.toString() ??
                                              'Could not add song',
                                        ),
                                        backgroundColor: Colors.red[700],
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (_playlist?['name'] ?? 'Playlist').toString();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => widget.onBack(false),
        ),
        title: Text(name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') {
                _renamePlaylist();
              } else if (value == 'download') {
                _downloadPlaylistLibrary();
              } else if (value == 'delete') {
                _deletePlaylist();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'download', child: Text('Download library')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSongsSheet,
        backgroundColor: const Color(0xFF0B3B8C),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Songs'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0B3B8C)),
            )
          : _songs.isEmpty
              ? Center(
                  child: Text(
                    'No songs in this playlist yet',
                    style: TextStyle(color: Colors.grey[400], fontSize: 16),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPlaylist,
                  color: const Color(0xFF0B3B8C),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: _songs.length,
                    itemBuilder: (context, index) {
                      final song = _songs[index];
                      return Dismissible(
                        key: ValueKey('${song.id}-${index.toString()}'),
                        background: Container(
                          color: Colors.red[700],
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: const Icon(Icons.delete_rounded,
                              color: Colors.white),
                        ),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          await _removeSong(song);
                          return false;
                        },
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          title: SongTile(
                            song: song,
                            onTap: () async {
                              await _activity.recordPlaylistPlay(
                                playlistId: widget.playlistId,
                                playlistName:
                                    (_playlist?['name'] ?? 'Playlist').toString(),
                                coverUrl: song.coverUrl,
                              );
                              widget.onSongSelected(song, _songs);
                            },
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'add_to_queue') {
                                final messenger = ScaffoldMessenger.of(context);
                                final added =
                                    await widget.onAddToQueue(song, _songs);
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      added
                                          ? 'Added to queue'
                                          : 'Song is already in queue',
                                    ),
                                    backgroundColor: added
                                        ? Colors.green[700]
                                        : Colors.orange[700],
                                  ),
                                );
                              } else if (value == 'remove') {
                                await _confirmAndRemoveSong(song);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'add_to_queue',
                                child: Text('Add to queue'),
                              ),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove from playlist'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
