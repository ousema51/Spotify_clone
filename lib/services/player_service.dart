import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import 'player_notification_service.dart';

enum PlayerPlaybackState { idle, loading, playing, paused, completed, error }

class PlayerService {
  static final PlayerService _instance = PlayerService._internal();
  factory PlayerService() => _instance;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final ValueNotifier<PlayerPlaybackState> playbackStateNotifier =
      ValueNotifier(PlayerPlaybackState.idle);
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> durationNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> bufferedPositionNotifier = ValueNotifier(
    Duration.zero,
  );

  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _bufferedPositionSubscription;
  Song? _currentSong;
  final PlayerNotificationService _notification = PlayerNotificationService();
  Future<void> Function()? _onSkipToNextRequested;
  Future<void> Function()? _onSkipToPreviousRequested;
  bool _canSkipNext = false;
  bool _canSkipPrevious = false;
  int _lastNotifiedPositionSecond = -1;

  PlayerService._internal() {
    _stateSubscription = _audioPlayer.playerStateStream.listen(
      _onPlayerStateChanged,
      onError: (error, stackTrace) {
        playbackStateNotifier.value = PlayerPlaybackState.error;
        _pushNotificationState();
      },
    );

    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      positionNotifier.value = position;
      final second = position.inSeconds;
      if (second != _lastNotifiedPositionSecond) {
        _lastNotifiedPositionSecond = second;
        _pushNotificationState();
      }
    });

    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      durationNotifier.value = duration ?? Duration.zero;
      _pushNotificationState();
    });

    _bufferedPositionSubscription = _audioPlayer.bufferedPositionStream.listen((
      buffered,
    ) {
      bufferedPositionNotifier.value = buffered;
      _pushNotificationState();
    });

    _notification.bindControlCallbacks(
      onPlayRequested: () async {
        await play();
      },
      onPauseRequested: () async {
        await pause();
      },
      onStopRequested: () async {
        await stop();
      },
      onSkipToNextRequested: () async {
        final callback = _onSkipToNextRequested;
        if (callback != null) {
          await callback();
        }
      },
      onSkipToPreviousRequested: () async {
        final callback = _onSkipToPreviousRequested;
        if (callback != null) {
          await callback();
        }
      },
      onSeekRequested: (position) async {
        await seek(position);
      },
    );
  }

  Song? get currentSong => _currentSong;

  bool get hasSource => _audioPlayer.audioSource != null;

  bool get isPlaying => _audioPlayer.playing;

  void setSkipHandlers({
    Future<void> Function()? onSkipToNextRequested,
    Future<void> Function()? onSkipToPreviousRequested,
  }) {
    _onSkipToNextRequested = onSkipToNextRequested;
    _onSkipToPreviousRequested = onSkipToPreviousRequested;
  }

  void setTransportAvailability({
    required bool canSkipNext,
    required bool canSkipPrevious,
  }) {
    _canSkipNext = canSkipNext;
    _canSkipPrevious = canSkipPrevious;
    _pushNotificationState();
  }

  void _onPlayerStateChanged(PlayerState state) {
    switch (state.processingState) {
      case ProcessingState.idle:
        playbackStateNotifier.value = PlayerPlaybackState.idle;
        break;
      case ProcessingState.loading:
      case ProcessingState.buffering:
        playbackStateNotifier.value = PlayerPlaybackState.loading;
        break;
      case ProcessingState.ready:
        playbackStateNotifier.value = state.playing
            ? PlayerPlaybackState.playing
            : PlayerPlaybackState.paused;
        break;
      case ProcessingState.completed:
        playbackStateNotifier.value = PlayerPlaybackState.completed;
        break;
    }

    _pushNotificationState();
  }

  Map<String, String>? _normalizeHeaders(Map<String, dynamic>? rawHeaders) {
    if (rawHeaders == null || rawHeaders.isEmpty) {
      return null;
    }

    final headers = <String, String>{};
    rawHeaders.forEach((key, value) {
      final k = key.toString().trim();
      final v = value.toString().trim();
      if (k.isNotEmpty && v.isNotEmpty) {
        headers[k] = v;
      }
    });

    return headers.isEmpty ? null : headers;
  }

  Future<void> playStream({
    required Song song,
    required String audioUrl,
    Map<String, dynamic>? headers,
  }) async {
    final trimmedUrl = audioUrl.trim();
    if (trimmedUrl.isEmpty) {
      throw StateError('audioUrl cannot be empty');
    }

    _currentSong = song;
    playbackStateNotifier.value = PlayerPlaybackState.loading;
    positionNotifier.value = Duration.zero;
    bufferedPositionNotifier.value = Duration.zero;
    _lastNotifiedPositionSecond = -1;
    _pushNotificationState();

    final source = AudioSource.uri(
      Uri.parse(trimmedUrl),
      headers: _normalizeHeaders(headers),
    );

    await _audioPlayer.stop();
    await _audioPlayer.setAudioSource(source);
    await _audioPlayer.play();
    _pushNotificationState();
  }

  Future<void> playLocalFile({
    required Song song,
    required String filePath,
  }) async {
    final trimmedPath = filePath.trim();
    if (trimmedPath.isEmpty) {
      throw StateError('filePath cannot be empty');
    }

    final file = File(trimmedPath);
    if (!await file.exists()) {
      throw StateError('Cached audio file not found');
    }

    _currentSong = song;
    playbackStateNotifier.value = PlayerPlaybackState.loading;
    positionNotifier.value = Duration.zero;
    bufferedPositionNotifier.value = Duration.zero;
    _lastNotifiedPositionSecond = -1;
    _pushNotificationState();

    await _audioPlayer.stop();
    await _audioPlayer.setFilePath(trimmedPath);
    await _audioPlayer.play();
    _pushNotificationState();
  }

  Future<void> play() async {
    if (_audioPlayer.audioSource == null) {
      return;
    }
    await _audioPlayer.play();
    _pushNotificationState();
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
    _pushNotificationState();
  }

  Future<void> seek(Duration position) async {
    if (_audioPlayer.audioSource == null) {
      return;
    }

    await _audioPlayer.seek(position);
    _pushNotificationState();
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    _currentSong = null;
    positionNotifier.value = Duration.zero;
    bufferedPositionNotifier.value = Duration.zero;
    durationNotifier.value = Duration.zero;
    playbackStateNotifier.value = PlayerPlaybackState.idle;
    _canSkipNext = false;
    _canSkipPrevious = false;
    _lastNotifiedPositionSecond = -1;
    await _notification.clearNowPlaying();
  }

  void _pushNotificationState() {
    final song = _currentSong;
    if (song == null) {
      return;
    }

    final state = playbackStateNotifier.value;
    unawaited(
      _notification.updateNowPlaying(
        song: song,
        isPlaying: state == PlayerPlaybackState.playing,
        isLoading: state == PlayerPlaybackState.loading,
        isCompleted: state == PlayerPlaybackState.completed,
        canSkipNext: _canSkipNext,
        canSkipPrevious: _canSkipPrevious,
        position: positionNotifier.value,
        bufferedPosition: bufferedPositionNotifier.value,
        duration: durationNotifier.value > Duration.zero
            ? durationNotifier.value
            : (song.duration != null && song.duration! > 0
                  ? Duration(seconds: song.duration!)
                  : null),
      ),
    );
  }

  Future<void> disposePlayer() async {
    await _stateSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _bufferedPositionSubscription?.cancel();
    await _audioPlayer.dispose();
    positionNotifier.dispose();
    durationNotifier.dispose();
    bufferedPositionNotifier.dispose();
    playbackStateNotifier.dispose();
  }
}
