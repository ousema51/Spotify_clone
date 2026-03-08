import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../services/music_service.dart';

class MiniPlayer extends StatefulWidget {
  final Song? currentSong;
  final VoidCallback onTap;

  const MiniPlayer({super.key, required this.onTap, this.currentSong});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  bool _isPlaying = false;
  bool _isLiked = false;
  late AnimationController _progressController;
  final MusicService _musicService = MusicService();

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _checkLiked();
  }

  @override
  void didUpdateWidget(MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSong?.id != widget.currentSong?.id) {
      _progressController.reset();
      _isPlaying = false;
      _checkLiked();
    }
  }

  Future<void> _checkLiked() async {
    if (widget.currentSong == null) return;
    final liked = await _musicService.checkLiked(widget.currentSong!.id);
    if (mounted) setState(() => _isLiked = liked);
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _progressController.forward();
      } else {
        _progressController.stop();
      }
    });
  }

  Future<void> _toggleLike() async {
    if (widget.currentSong == null) return;
    final song = widget.currentSong!;
    if (_isLiked) {
      await _musicService.unlikeSong(song.id);
    } else {
      await _musicService.likeSong(song.id, song.toMetadata());
    }
    if (mounted) setState(() => _isLiked = !_isLiked);
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.currentSong;
    final title = song?.title ?? 'No song selected';
    final artist = song?.artist ?? '';

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A2A2A), Color(0xFF1E1E1E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
              child: Row(
                children: [
                  // Album Art
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: song?.coverUrl != null &&
                              song!.coverUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: song.coverUrl!,
                              placeholder: (context, url) =>
                                  Container(color: Colors.grey[800]),
                              errorWidget: (context, url, error) => Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF1DB954),
                                      Color(0xFF148A3D)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: const Icon(Icons.music_note_rounded,
                                    color: Colors.white, size: 24),
                              ),
                              fit: BoxFit.cover,
                            )
                          : Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF1DB954),
                                    Color(0xFF148A3D)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(Icons.music_note_rounded,
                                  color: Colors.white, size: 24),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Song info
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontSize: 14,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (artist.isNotEmpty)
                          Text(
                            artist,
                            style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                                letterSpacing: 0.1),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),

                  // Like button
                  IconButton(
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        key: ValueKey(_isLiked),
                        color: _isLiked
                            ? const Color(0xFF1DB954)
                            : Colors.grey[400],
                        size: 22,
                      ),
                    ),
                    onPressed: song != null ? _toggleLike : null,
                    splashRadius: 20,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),

                  // Play/Pause button
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey(_isPlaying),
                          color: Colors.black,
                          size: 20,
                        ),
                      ),
                      onPressed: _togglePlay,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),

            // Progress bar
            AnimatedBuilder(
              animation: _progressController,
              builder: (context, child) {
                return Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: Colors.grey[800],
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor:
                          _progressController.value.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: const Color(0xFF1DB954),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
