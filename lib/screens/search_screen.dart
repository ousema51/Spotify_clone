import 'package:flutter/material.dart';
import 'dart:async';
import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../services/music_service.dart';
import '../services/user_activity_service.dart';
import '../widgets/song_tile.dart';

class SearchScreen extends StatefulWidget {
  final void Function(Song, [List<Song>?]) onSongSelected;
  final ValueChanged<String> onArtistSelected;
  final ValueChanged<String> onAlbumSelected;

  const SearchScreen({
    super.key,
    required this.onSongSelected,
    required this.onArtistSelected,
    required this.onAlbumSelected,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final MusicService _musicService = MusicService();
  final UserActivityService _activityService = UserActivityService();
  Timer? _debounce;

  List<Song> _songResults = [];
  List<Song> _recentSelectedSongs = [];
  List<Album> _albumResults = [];
  List<Artist> _artistResults = [];
  List<Map<String, dynamic>> _playlists = [];
  Set<String> _likedSongIds = <String>{};
  bool _isSearching = false;
  bool _hasSearched = false;

  final List<String> _genres = [
    'Pop',
    'Hip Hop',
    'Rock',
    'Indie',
    'Jazz',
    'Electronic',
    'Classical',
    'R&B',
  ];

  final List<Color> _genreColors = [
    const Color(0xFFE91E63),
    const Color(0xFFBA68C8),
    const Color(0xFFEF5350),
    const Color(0xFF66BB6A),
    const Color(0xFFFFCA28),
    const Color(0xFF29B6F6),
    const Color(0xFF8D6E63),
    const Color(0xFF7E57C2),
  ];

  @override
  void initState() {
    super.initState();
    _loadRecentSelections();
    _loadSongActionState();
  }

  Future<void> _loadSongActionState() async {
    try {
      final likedSongsFuture = _musicService.getLikedSongs();
      final playlistsFuture = _musicService.getMyPlaylists();

      final likedSongs = await likedSongsFuture;
      final playlists = await playlistsFuture;

      if (!mounted) return;
      setState(() {
        _playlists = playlists;
        _likedSongIds = likedSongs
            .map((song) => song.id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
      });
    } catch (_) {}
  }

  int _playlistSongCount(Map<String, dynamic> playlist) {
    final songs = playlist['songs'];
    return songs is List ? songs.length : 0;
  }

  Future<void> _showChoosePlaylistForSong(Song song) async {
    List<Map<String, dynamic>> playlists = _playlists;
    try {
      final freshPlaylists = await _musicService.getMyPlaylists();
      if (freshPlaylists.isNotEmpty || playlists.isEmpty) {
        playlists = freshPlaylists;
      }
      if (mounted) {
        setState(() {
          _playlists = freshPlaylists;
        });
      }
    } catch (_) {}

    if (!mounted) return;

    if (playlists.isEmpty) {
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
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final playlistName =
                  (playlist['name'] ?? 'Untitled Playlist').toString();
              final playlistId = (playlist['_id'] ?? '').toString().trim();

              return ListTile(
                leading: const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white70,
                ),
                title: Text(playlistName),
                subtitle: Text(
                  '${_playlistSongCount(playlist)} songs',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                onTap: () async {
                  final navigator = Navigator.of(parentContext);
                  final messenger = ScaffoldMessenger.of(parentContext);

                  final result = await _musicService.addSongToPlaylist(
                    playlistId,
                    song,
                  );

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

  Future<void> _addSongToLiked(Song song) async {
    final songId = song.id.trim();
    if (songId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cannot like this song'),
          backgroundColor: Colors.red[700],
        ),
      );
      return;
    }

    final alreadyLiked = _likedSongIds.contains(songId);
    if (alreadyLiked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Song is already in liked songs'),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    final result = await _musicService.likeSong(songId, song.toMetadata());
    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _likedSongIds.add(songId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Added to liked songs'),
          backgroundColor: Colors.green[700],
        ),
      );
      return;
    }

    final message = (result['message'] ?? 'Could not add to liked songs')
        .toString();
    final isAlreadyLikedMessage = message.toLowerCase().contains('already');
    if (isAlreadyLikedMessage) {
      setState(() {
        _likedSongIds.add(songId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  Future<void> _removeSongFromLiked(Song song) async {
    final songId = song.id.trim();
    if (songId.isEmpty) {
      return;
    }

    final result = await _musicService.unlikeSong(songId);
    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _likedSongIds.remove(songId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Removed from liked songs'),
          backgroundColor: Colors.green[700],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['message']?.toString() ?? 'Could not remove from liked songs',
        ),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  Future<void> _removeSongFromRecentSelections(Song song) async {
    final songId = song.id.trim();
    if (songId.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _recentSelectedSongs.removeWhere((s) => s.id == songId);
      });
    }

    await _activityService.removeRecentSearchSong(songId);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Removed from recent searches'),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  Widget _buildSongResultItem(
    Song song,
    List<Song> queue, {
    bool isRecentSelection = false,
  }) {
    final songId = song.id.trim();
    final isLiked = songId.isNotEmpty && _likedSongIds.contains(songId);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      title: SongTile(
        song: song,
        onTap: () => _onSongSelectedFromSearch(song, queue),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'add_to_playlist') {
            _showChoosePlaylistForSong(song);
          } else if (value == 'add_to_liked') {
            _addSongToLiked(song);
          } else if (value == 'remove_from_liked') {
            _removeSongFromLiked(song);
          } else if (value == 'remove_from_recent') {
            _removeSongFromRecentSelections(song);
          }
        },
        itemBuilder: (context) {
          final items = <PopupMenuEntry<String>>[
            const PopupMenuItem(
              value: 'add_to_playlist',
              child: Text('Add to playlist'),
            ),
            PopupMenuItem(
              value: isLiked ? 'remove_from_liked' : 'add_to_liked',
              child: Text(
                isLiked ? 'Remove from liked songs' : 'Add to liked songs',
              ),
            ),
          ];

          if (isRecentSelection) {
            items.add(
              const PopupMenuItem(
                value: 'remove_from_recent',
                child: Text('Remove from recent searches'),
              ),
            );
          }

          return items;
        },
      ),
    );
  }

  Future<void> _loadRecentSelections() async {
    final items = await _activityService.getRecentSearchSongs();
    if (!mounted) return;
    setState(() => _recentSelectedSongs = items);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _onSongSelectedFromSearch(Song song, List<Song> queue) async {
    // Trigger playback/navigation immediately.
    widget.onSongSelected(song, queue);

    // Update local recent list optimistically.
    if (mounted) {
      setState(() {
        _recentSelectedSongs.removeWhere((s) => s.id == song.id);
        _recentSelectedSongs.insert(0, song);
      });
    }

    // Persist and reload so the recent section reflects durable state.
    await _activityService.recordSearchSongSelection(song);
    await _loadRecentSelections();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _songResults = [];
        _albumResults = [];
        _artistResults = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final songsFuture = _musicService.searchSongs(query);
      final artistsFuture = _musicService.searchArtists(query);
      final albumsFuture = _musicService.searchAlbums(query);

      final songs = await songsFuture;
      final artists = await artistsFuture;
      final albums = await albumsFuture;
      if (mounted) {
        setState(() {
          _songResults = songs;
          _artistResults = artists;
          _albumResults = albums;
          _hasSearched = true;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Search',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                // Update UI (clear button) immediately
                if (mounted) setState(() {});
                // Debounce the search calls
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () {
                  if (_searchController.text == value) {
                    _search(value);
                  }
                });
              },
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'What do you want to listen to?',
                hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400]),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          color: Colors.grey[400],
                        ),
                        onPressed: () {
                          _searchController.clear();
                          if (mounted) setState(() {});
                          _search('');
                          _loadRecentSelections();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF282828),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 20),
            if (_isSearching)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF0B3B8C)),
              )
            else if (_searchController.text.trim().isEmpty &&
                _recentSelectedSongs.isNotEmpty)
              Expanded(child: _buildRecentSelections())
            else if (_hasSearched)
              Expanded(child: _buildSearchResults())
            else
              Expanded(child: _buildBrowseAll()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return ListView(
      children: [
        if (_songResults.isNotEmpty) ...[
          const Text(
            'Songs',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._songResults.map(
            (song) => _buildSongResultItem(song, _songResults),
          ),
          const SizedBox(height: 20),
        ],
        if (_artistResults.isNotEmpty) ...[
          const Text(
            'Artists',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._artistResults.map(
            (artist) => ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF282828),
                child: Icon(Icons.person_rounded, color: Colors.white70),
              ),
              title: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('Artist'),
              onTap: () => widget.onArtistSelected(artist.id),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (_albumResults.isNotEmpty) ...[
          const Text(
            'Albums',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._albumResults.map(
            (album) => ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF282828),
                child: Icon(Icons.album_rounded, color: Colors.white70),
              ),
              title: Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(album.artist ?? 'Album'),
              onTap: () => widget.onAlbumSelected(album.id),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (_songResults.isEmpty &&
            _artistResults.isEmpty &&
            _albumResults.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'No results found',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentSelections() {
    return ListView(
      children: [
        const Text(
          'Recent Selections',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._recentSelectedSongs.map(
          (song) => _buildSongResultItem(
            song,
            _recentSelectedSongs,
            isRecentSelection: true,
          ),
        ),
      ],
    );
  }

  Widget _buildBrowseAll() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Browse all',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.builder(
            itemCount: _genres.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.8,
            ),
            itemBuilder: (context, index) {
              final color = _genreColors[index];
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    _genres[index],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
