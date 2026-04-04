import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../services/music_service.dart';
import '../services/player_service.dart';

class FullPlayerScreen extends StatefulWidget {
  final VoidCallback onClose;
  final Song? currentSong;
  final bool isShuffle;
  final QueueRepeatMode repeatMode;
  final VoidCallback onToggleShuffle;
  final VoidCallback onCycleRepeatMode;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final Future<void> Function(String?) onArtistTap;

  const FullPlayerScreen({
    super.key,
    required this.onClose,
    this.currentSong,
    required this.isShuffle,
    required this.repeatMode,
    required this.onToggleShuffle,
    required this.onCycleRepeatMode,
    required this.onNext,
    required this.onPrevious,
    required this.onArtistTap,
  });

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen>
    with TickerProviderStateMixin {
  bool _isPlaying = false;
  bool _isLiked = false;
  double _currentSliderValue = 0.0;
  bool _isSeeking = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  final MusicService _musicService = MusicService();
  final PlayerService _player = PlayerService();

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );
    _slideController.forward();
    _checkLiked();
    _isPlaying = _player.isPlaying;
    _position = _player.position;
    _duration = _player.duration;
    _syncProgressFromPlayer();
    
    // Listen to player state changes
    _player.playingNotifier.addListener(_onPlayerStateChanged);
    _player.positionNotifier.addListener(_onPlayerProgressChanged);
    _player.durationNotifier.addListener(_onPlayerProgressChanged);
  }

  void _onPlayerStateChanged() {
    if (mounted) {
      setState(() => _isPlaying = _player.isPlaying);
    }
  }

  void _syncProgressFromPlayer() {
    _position = _player.position;
    _duration = _player.duration;
    if (!_isSeeking) {
      final totalMs = _duration.inMilliseconds;
      _currentSliderValue = totalMs > 0
          ? (_position.inMilliseconds / totalMs).clamp(0.0, 1.0)
          : 0.0;
    }
  }

  void _onPlayerProgressChanged() {
    if (!mounted) return;
    setState(_syncProgressFromPlayer);
  }

  @override
  void didUpdateWidget(FullPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSong?.id != widget.currentSong?.id) {
      _checkLiked();
      _isSeeking = false;
      _syncProgressFromPlayer();
    }
  }

  Future<void> _checkLiked() async {
    if (widget.currentSong == null) return;
    try {
      final liked = await _musicService.checkLiked(widget.currentSong!.id);
      if (mounted) setState(() => _isLiked = liked);
    } catch (e) {
      debugPrint('Error checking liked status: $e');
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _player.playingNotifier.removeListener(_onPlayerStateChanged);
    _player.positionNotifier.removeListener(_onPlayerProgressChanged);
    _player.durationNotifier.removeListener(_onPlayerProgressChanged);
    super.dispose();
  }

  void _close() async {
    await _slideController.reverse();
    widget.onClose();
  }

  Future<void> _toggleLike() async {
    if (widget.currentSong == null) return;
    final song = widget.currentSong!;
    try {
      if (_isLiked) {
        await _musicService.unlikeSong(song.id);
      } else {
        await _musicService.likeSong(song.id, song.toMetadata());
      }
      if (mounted) setState(() => _isLiked = !_isLiked);
    } catch (e) {
      debugPrint('Error toggling like: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDurationValue(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
              colors: [Color(0xFF1A3A2A), Color(0xFF0D1B14), Color(0xFF121212)],
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
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 32,
                            color: Colors.white,
                          ),
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: Colors.grey[300],
                          ),
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
                          color: const Color(0xFF0B3B8C).withOpacity(0.25),
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
                    child: song?.coverUrl != null && song!.coverUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: song.coverUrl!,
                            placeholder: (context, url) => Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF0B3B8C),
                                    Color(0xFF0A5C2B),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF0B3B8C),
                                    Color(0xFF0A5C2B),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.music_note_rounded,
                                  color: Colors.white70,
                                  size: 80,
                                ),
                              ),
                            ),
                            fit: BoxFit.cover,
                          )
                        : Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF0B3B8C), Color(0xFF0A5C2B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.music_note_rounded,
                                color: Colors.white70,
                                size: 80,
                              ),
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
                            InkWell(
                              onTap: () => widget.onArtistTap(song?.artist),
                              child: Text(
                                song?.artist ?? 'Unknown Artist',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[400],
                                  letterSpacing: 0.2,
                                  decoration: TextDecoration.underline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            key: ValueKey(_isLiked),
                            color: _isLiked
                                ? const Color(0xFF0B3B8C)
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
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _currentSliderValue.clamp(0.0, 1.0),
                      onChangeStart: (_) {
                        setState(() => _isSeeking = true);
                      },
                      onChanged: (val) {
                        setState(() => _currentSliderValue = val.clamp(0.0, 1.0));
                      },
                      onChangeEnd: (val) async {
                        await _player.seekToFraction(val);
                        if (mounted) {
                          setState(() => _isSeeking = false);
                        }
                      },
                    ),
                  ),

                  // Time labels
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDurationValue(
                            Duration(
                              milliseconds: (_duration.inMilliseconds *
                                      _currentSliderValue)
                                  .round(),
                            ),
                          ),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _formatDurationValue(_duration),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
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
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: widget.isShuffle
                              ? const Color(0xFF0B3B8C)
                              : Colors.grey[400],
                          size: 24,
                        ),
                        onPressed: widget.onToggleShuffle,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.skip_previous_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                        onPressed: widget.onPrevious,
                      ),
                      GestureDetector(
                        onTap: () async {
                          if (_isPlaying) {
                            await _player.pause();
                          } else {
                            await _player.play();
                          }
                        },
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
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                        onPressed: widget.onNext,
                      ),
                      IconButton(
                        icon: Icon(
                            widget.repeatMode == QueueRepeatMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                            color: widget.repeatMode != QueueRepeatMode.off
                              ? const Color(0xFF0B3B8C)
                              : Colors.grey[400],
                          size: 24,
                        ),
                        onPressed: widget.onCycleRepeatMode,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Bottom actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.devices_rounded,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                        onPressed: () {},
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.share_rounded,
                              color: Colors.grey[400],
                              size: 20,
                            ),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.queue_music_rounded,
                              color: Colors.grey[400],
                              size: 20,
                            ),
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
