import 'package:flutter/material.dart';
import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../services/music_service.dart';
import '../widgets/song_tile.dart';
import '../widgets/album_card.dart';
import 'album_screen.dart';
import 'artist_screen.dart';

class SearchScreen extends StatefulWidget {
  final Function(Song) onSongSelected;

  const SearchScreen({super.key, required this.onSongSelected});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final MusicService _musicService = MusicService();

  List<Song> _songResults = [];
  List<Album> _albumResults = [];
  List<Artist> _artistResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  final List<String> _genres = [
    'Pop', 'Hip Hop', 'Rock', 'Indie',
    'Jazz', 'Electronic', 'Classical', 'R&B',
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      final songs = await _musicService.searchSongs(query);
      List<Album> albums = [];
      List<Artist> artists = [];
      try {
        albums = await _musicService.searchAlbums(query);
      } catch (_) {}
      try {
        artists = await _musicService.searchArtists(query);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _songResults = songs;
          _albumResults = albums;
          _artistResults = artists;
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
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (_searchController.text == value) {
                    _search(value);
                  }
                });
              },
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'What do you want to listen to?',
                hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon:
                    Icon(Icons.search_rounded, color: Colors.grey[400]),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded,
                            color: Colors.grey[400]),
                        onPressed: () {
                          _searchController.clear();
                          _search('');
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
                child: CircularProgressIndicator(color: Color(0xFF1DB954)),
              )
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
          ..._songResults.map((song) => SongTile(
                song: song,
                onTap: () => widget.onSongSelected(song),
              )),
          const SizedBox(height: 20),
        ],
        if (_albumResults.isNotEmpty) ...[
          const Text(
            'Albums',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _albumResults.length,
              itemBuilder: (context, index) {
                final album = _albumResults[index];
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
          const SizedBox(height: 20),
        ],
        if (_artistResults.isNotEmpty) ...[
          const Text(
            'Artists',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._artistResults.map((artist) => ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                leading: CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF282828),
                  backgroundImage: artist.imageUrl != null
                      ? NetworkImage(artist.imageUrl!)
                      : null,
                  child: artist.imageUrl == null
                      ? const Icon(Icons.person_rounded,
                          color: Colors.white54)
                      : null,
                ),
                title: Text(
                  artist.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text('Artist',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ArtistScreen(
                      artistId: artist.id,
                      onSongSelected: widget.onSongSelected,
                    ),
                  ),
                ),
              )),
        ],
        if (_songResults.isEmpty &&
            _albumResults.isEmpty &&
            _artistResults.isEmpty)
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
                    colors: [color, color.withOpacity(0.7)],
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
