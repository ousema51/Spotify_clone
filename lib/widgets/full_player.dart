import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../services/music_service.dart';

class FullPlayerScreen extends StatefulWidget {
  final VoidCallback onClose;
  final Song? currentSong;

  const FullPlayerScreen({
    super.key,
    required this.onClose,
    this.currentSong,
  });

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen>
    with TickerProviderStateMixin {
  bool _isPlaying = false;
  bool _isLiked = false;
  bool _isShuffle = false;
  int _repeatMode = 0;
  double _currentSliderValue = 0.0;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  final MusicService _musicService = MusicService();

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward();
    _checkLiked();
  }

  @override
  void didUpdateWidget(FullPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSong?.id != widget.currentSong?.id) {
      _currentSliderValue = 0.0;
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
    _slideController.dispose();
    super.dispose();
  }

  void _close() async {
    await _slideController.reverse();
    widget.onClose();
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

  String _formatTime(double fraction) {
    final totalDuration = widget.currentSong?.duration ?? 230;
    final int totalSeconds = (fraction * totalDuration).toInt();
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '3:50';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.currentSong;

    return SlideTransition(
      position: _slideAnimation,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF1A3A2A),
                Color(0xFF0D1B14),
                Color(0xFF121212)
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.4, 0.8],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              size: 32, color: Colors.white),
                          onPressed: _close,
                        ),
                        Column(
                          children: [
                            Text(
                              'NOW PLAYING',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.2,
                                color: Colors.grey[400],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song?.albumName ?? "Music",
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.more_vert_rounded,
                              color: Colors.grey[300]),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Album art
                  Container(
                    width: MediaQuery.of(context).size.width * 0.78,
                    height: MediaQuery.of(context).size.width * 0.78,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1DB954).withOpacity(0.25),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                          spreadRadius: 4,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: song?.coverUrl != null &&
                            song!.coverUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: song.coverUrl!,
                            placeholder: (context, url) => Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF1DB954),
                                    Color(0xFF0A5C2B)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF1DB954),
                                    Color(0xFF0A5C2B)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: Icon(Icons.music_note_rounded,
                                    color: Colors.white70, size: 80),
                              ),
                            ),
                            fit: BoxFit.cover,
                          )
                        : Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFF1DB954),
                                  Color(0xFF0A5C2B)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.music_note_rounded,
                                  color: Colors.white70, size: 80),
                            ),
                          ),
                  ),

                  const Spacer(flex: 2),

                  // Song info and like
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song?.title ?? 'No song selected',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              song?.artist ?? '',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[400],
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: Icon(
                            _isLiked
                                ? Icons.favorite
                                : Icons.favorite_border,
                            key: ValueKey(_isLiked),
                            color: _isLiked
                                ? const Color(0xFF1DB954)
                                : Colors.grey[400],
                            size: 28,
                          ),
                        ),
                        onPressed: song != null ? _toggleLike : null,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.grey[700],
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _currentSliderValue,
                      onChanged: (val) =>
                          setState(() => _currentSliderValue = val),
                    ),
                  ),

                  // Time labels
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatTime(_currentSliderValue),
                          style: TextStyle(
                              color: Colors.grey[400], fontSize: 12),
                        ),
                        Text(
                          _formatDuration(song?.duration),
                          style: TextStyle(
                              color: Colors.grey[400], fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.shuffle_rounded,
                            color: _isShuffle
                                ? const Color(0xFF1DB954)
                                : Colors.grey[400],
                            size: 24),
                        onPressed: () =>
                            setState(() => _isShuffle = !_isShuffle),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded,
                            color: Colors.white, size: 36),
                        onPressed: () {},
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _isPlaying = !_isPlaying),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(scale: anim, child: child),
                            child: Icon(
                              _isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              key: ValueKey(_isPlaying),
                              color: Colors.black,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded,
                            color: Colors.white, size: 36),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: Icon(
                          _repeatMode == 2
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: _repeatMode > 0
                              ? const Color(0xFF1DB954)
                              : Colors.grey[400],
                          size: 24,
                        ),
                        onPressed: () => setState(
                            () => _repeatMode = (_repeatMode + 1) % 3),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Bottom actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.devices_rounded,
                            color: Colors.grey[400], size: 20),
                        onPressed: () {},
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.share_rounded,
                                color: Colors.grey[400], size: 20),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: Icon(Icons.queue_music_rounded,
                                color: Colors.grey[400], size: 20),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
